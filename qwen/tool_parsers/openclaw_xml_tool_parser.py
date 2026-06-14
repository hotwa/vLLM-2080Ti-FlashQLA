import json
from collections.abc import Sequence
from dataclasses import dataclass

from vllm.entrypoints.openai.chat_completion.protocol import (
    ChatCompletionRequest,
)
from vllm.entrypoints.openai.engine.protocol import (
    DeltaFunctionCall,
    DeltaMessage,
    DeltaToolCall,
    ExtractedToolCallInformation,
)
from vllm.logger import init_logger
from vllm.tool_parsers.abstract_tool_parser import ToolParserManager
from vllm.tool_parsers.qwen3coder_tool_parser import Qwen3CoderToolParser

logger = init_logger(__name__)


@dataclass
class ToolBlock:
    start: int
    end: int
    text: str
    complete: bool


@ToolParserManager.register_module("openclaw_xml")
class OpenClawXMLToolParser(Qwen3CoderToolParser):
    """
    Relaxed XML parser for OpenClaw/OpenCode workflows.

    It keeps the upstream qwen3_coder behavior, but it also accepts bare
    <function=...>...</function> blocks during streaming instead of requiring
    an outer <tool_call> wrapper to appear first.
    """

    _KNOWN_CLOSING_TAG_TAILS = (
        "</parameter>",
        "</function>",
        "</tool_call>",
        "</tool call>",
        "</tool_result>",
        "</tool_name>",
        "</tool_call_id>",
        "</arg_key>",
        "</arg_value>",
    )

    def _reset_streaming_state(self):
        super()._reset_streaming_state()
        # Track how much plain text has been safely emitted while we wait to see
        # whether a partial "<function"/"<tool_call" prefix becomes a tool call.
        self._emitted_content_len = 0
        # Hold possible leaked closing-tag tails until we know whether they are
        # just internal tag fragments from the next chunk.
        self._pending_tail_text = ""

    def _get_pending_tool_prefix_length(self, text: str) -> int:
        max_len = 0
        for token in (self.tool_call_start_token, self.tool_call_prefix):
            upper = min(len(text), len(token) - 1)
            for size in range(1, upper + 1):
                if text.endswith(token[:size]):
                    max_len = max(max_len, size)
        return max_len

    def _extract_tool_blocks(self, text: str) -> list[ToolBlock]:
        blocks: list[ToolBlock] = []
        pos = 0

        while pos < len(text):
            wrapper_start = text.find(self.tool_call_start_token, pos)
            function_start = text.find(self.tool_call_prefix, pos)
            candidates = [idx for idx in (wrapper_start, function_start) if idx != -1]
            if not candidates:
                break

            start = min(candidates)
            if start == wrapper_start:
                end = text.find(
                    self.tool_call_end_token,
                    start + len(self.tool_call_start_token),
                )
                complete = end != -1
                block_end = (
                    end + len(self.tool_call_end_token) if complete else len(text)
                )
            else:
                end = text.find(
                    self.function_end_token,
                    start + len(self.tool_call_prefix),
                )
                complete = end != -1
                block_end = end + len(self.function_end_token) if complete else len(text)

            blocks.append(
                ToolBlock(
                    start=start,
                    end=block_end,
                    text=text[start:block_end],
                    complete=complete,
                )
            )
            pos = max(block_end, start + 1)

        return blocks

    def _split_trailing_tag_tail(self, text: str) -> tuple[str, str]:
        for tag in self._KNOWN_CLOSING_TAG_TAILS:
            for size in range(1, len(tag) + 1):
                suffix = tag[:size]
                if text.endswith(suffix):
                    return text[:-size], suffix
        return text, ""

    def _consume_known_closing_tags(self, text: str) -> tuple[str, str]:
        current = text
        while current:
            stripped = False
            for tag in self._KNOWN_CLOSING_TAG_TAILS:
                if current.startswith(tag):
                    current = current[len(tag) :]
                    stripped = True
                    break
            if stripped:
                continue

            if any(tag.startswith(current) for tag in self._KNOWN_CLOSING_TAG_TAILS):
                return "", current
            break

        return current, ""

    def _get_current_tool_block(self, text: str) -> ToolBlock | None:
        blocks = self._extract_tool_blocks(text)
        if self.current_tool_index >= len(blocks):
            return None
        return blocks[self.current_tool_index]

    def _extract_function_name(self, tool_text: str) -> str | None:
        if self.tool_call_prefix not in tool_text:
            return None

        func_start = tool_text.find(self.tool_call_prefix) + len(self.tool_call_prefix)
        func_end = tool_text.find(">", func_start)
        if func_end == -1:
            return None
        return tool_text[func_start:func_end]

    def _get_required_parameters(
        self,
        function_name: str,
        tools: Sequence[object] | None,
    ) -> list[str]:
        if not tools:
            return []

        for tool in tools:
            function_def = getattr(tool, "function", None)
            if function_def is None and isinstance(tool, dict):
                function_def = tool.get("function")

            if function_def is None:
                continue

            function_def_name = getattr(function_def, "name", None)
            if function_def_name is None and isinstance(function_def, dict):
                function_def_name = function_def.get("name")

            if function_def_name != function_name:
                continue

            parameters = getattr(function_def, "parameters", None)
            if parameters is None and isinstance(function_def, dict):
                parameters = function_def.get("parameters")

            required = getattr(parameters, "required", None)
            if required is None and isinstance(parameters, dict):
                required = parameters.get("required")
            required = required or []
            return [param for param in required if isinstance(param, str)]
        return []

    def _has_complete_parameter(self, tool_text: str, parameter_name: str) -> bool:
        parameter_token = f"{self.parameter_prefix}{parameter_name}>"
        search_start = 0

        while True:
            param_start = tool_text.find(parameter_token, search_start)
            if param_start == -1:
                return False

            value_start = param_start + len(parameter_token)
            if tool_text.find(self.parameter_end_token, value_start) != -1:
                return True

            search_start = value_start

    def _has_any_complete_parameter(self, tool_text: str) -> bool:
        search_start = 0

        while True:
            param_start = tool_text.find(self.parameter_prefix, search_start)
            if param_start == -1:
                return False

            name_start = param_start + len(self.parameter_prefix)
            name_end = tool_text.find(">", name_start)
            if name_end == -1:
                return False

            if tool_text.find(self.parameter_end_token, name_end + 1) != -1:
                return True

            search_start = name_end + 1

    def _is_bare_tool_call_ready(
        self,
        tool_text: str,
        tools: Sequence[object] | None,
    ) -> bool:
        stripped_text = tool_text.lstrip()
        if stripped_text.startswith(self.tool_call_start_token):
            return True

        function_name = self._extract_function_name(tool_text)
        if not function_name:
            return False

        required_parameters = self._get_required_parameters(function_name, tools)
        if required_parameters:
            return all(
                self._has_complete_parameter(tool_text, parameter_name)
                for parameter_name in required_parameters
            )

        return self._has_any_complete_parameter(tool_text) or (
            self.function_end_token in tool_text
        )

    def extract_tool_calls(
        self,
        model_output: str,
        request: ChatCompletionRequest,
    ) -> ExtractedToolCallInformation:
        if self.tool_call_prefix not in model_output:
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

        try:
            function_calls = self._get_function_calls(model_output)
            if not function_calls:
                return ExtractedToolCallInformation(
                    tools_called=False,
                    tool_calls=[],
                    content=model_output,
                )

            tool_calls = [
                self._parse_xml_function_call(function_call_str, request.tools)
                for function_call_str in function_calls
            ]

            self.prev_tool_call_arr.clear()
            for tool_call in tool_calls:
                if tool_call:
                    self.prev_tool_call_arr.append(
                        {
                            "name": tool_call.function.name,
                            "arguments": tool_call.function.arguments,
                        }
                    )

            blocks = self._extract_tool_blocks(model_output)
            content_index = (
                blocks[0].start if blocks else model_output.find(self.tool_call_prefix)
            )
            content = model_output[:content_index]
            valid_tool_calls = [tc for tc in tool_calls if tc is not None]
            return ExtractedToolCallInformation(
                tools_called=bool(valid_tool_calls),
                tool_calls=valid_tool_calls,
                content=content if content else None,
            )
        except Exception:
            logger.exception("Error in extracting tool call from response.")
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

    def extract_tool_calls_streaming(
        self,
        previous_text: str,
        current_text: str,
        delta_text: str,
        previous_token_ids: Sequence[int],
        current_token_ids: Sequence[int],
        delta_token_ids: Sequence[int],
        request: ChatCompletionRequest,
    ) -> DeltaMessage | None:
        if not previous_text:
            self._reset_streaming_state()
            self.streaming_request = request

        blocks = self._extract_tool_blocks(current_text)

        if not delta_text:
            if delta_token_ids and self.tool_call_end_token_id not in delta_token_ids:
                complete_calls = sum(1 for block in blocks if block.complete)
                if complete_calls > 0 and len(self.prev_tool_call_arr) > 0:
                    if all(block.complete for block in blocks):
                        return DeltaMessage(content="")
                elif not self.is_tool_call_started and current_text:
                    if self._emitted_content_len < len(current_text):
                        remaining_content = (
                            self._pending_tail_text
                            + current_text[self._emitted_content_len :]
                        )
                        self._emitted_content_len = len(current_text)
                        remaining_content, pending_tail = (
                            self._consume_known_closing_tags(remaining_content)
                        )
                        if pending_tail:
                            self._pending_tail_text = pending_tail
                            return None
                        self._pending_tail_text = ""
                        if remaining_content:
                            return DeltaMessage(content=remaining_content)
                    return DeltaMessage(content="")
            return None

        self.accumulated_text = current_text

        if self.json_closed and not self.in_function:
            current_block = self._get_current_tool_block(current_text)
            if current_block and current_block.complete:
                self.current_tool_index += 1
                self.header_sent = False
                self.param_count = 0
                self.json_started = False
                self.json_closed = False
                self.accumulated_params = {}

                if self.current_tool_index >= len(blocks):
                    self.is_tool_call_started = False
                return None

        if not self.is_tool_call_started:
            if blocks:
                self.is_tool_call_started = True
                first_start = blocks[0].start
                if self._emitted_content_len < first_start:
                    content_before = current_text[
                        self._emitted_content_len:first_start
                    ]
                    self._emitted_content_len = first_start
                    if content_before:
                        content_before = self._pending_tail_text + content_before
                        content_before, pending_tail = (
                            self._consume_known_closing_tags(content_before)
                        )
                        self._pending_tail_text = pending_tail
                        if content_before:
                            return DeltaMessage(content=content_before)
            else:
                if (
                    current_text.rstrip().endswith(self.tool_call_end_token)
                    and delta_text.strip() == ""
                ):
                    return None

                pending_prefix_len = self._get_pending_tool_prefix_length(current_text)
                safe_content_end = len(current_text) - pending_prefix_len

                if safe_content_end > self._emitted_content_len:
                    content_delta = current_text[
                        self._emitted_content_len:safe_content_end
                    ]
                    self._emitted_content_len = safe_content_end
                    if content_delta:
                        content_delta = self._pending_tail_text + content_delta
                        content_delta, pending_tail = self._consume_known_closing_tags(
                            content_delta
                        )
                        if pending_tail:
                            self._pending_tail_text = pending_tail
                            return None
                        content_delta, trailing_tail = self._split_trailing_tag_tail(
                            content_delta
                        )
                        self._pending_tail_text = trailing_tail
                        if content_delta:
                            return DeltaMessage(content=content_delta)
                return None

        current_block = self._get_current_tool_block(current_text)
        if current_block is None:
            return None

        tool_text = current_block.text

        if not self.header_sent:
            if self.tool_call_prefix in tool_text and self._is_bare_tool_call_ready(
                tool_text,
                self.streaming_request.tools if self.streaming_request else None,
            ):
                function_name = self._extract_function_name(tool_text)
                if function_name:
                    self.current_function_name = function_name
                    self.current_tool_id = self._generate_tool_call_id()
                    self.header_sent = True
                    self.in_function = True

                    final_arguments = "{}"
                    if current_block.complete:
                        function_calls = self._get_function_calls(tool_text)
                        if function_calls:
                            parsed_tool = self._parse_xml_function_call(
                                function_calls[0],
                                self.streaming_request.tools
                                if self.streaming_request
                                else None,
                            )
                            if parsed_tool:
                                final_arguments = parsed_tool.function.arguments

                    already_added = any(
                        tool.get("name") == self.current_function_name
                        for tool in self.prev_tool_call_arr
                    )
                    if not already_added:
                        self.prev_tool_call_arr.append(
                            {
                                "name": self.current_function_name,
                                "arguments": final_arguments,
                            }
                        )

                    return DeltaMessage(
                        tool_calls=[
                            DeltaToolCall(
                                index=self.current_tool_index,
                                id=self.current_tool_id,
                                function=DeltaFunctionCall(
                                    name=self.current_function_name,
                                    arguments="",
                                ),
                                type="function",
                            )
                        ]
                    )
            return None

        if self.in_function:
            if not self.json_started:
                self.json_started = True
                return DeltaMessage(
                    tool_calls=[
                        DeltaToolCall(
                            index=self.current_tool_index,
                            function=DeltaFunctionCall(arguments="{"),
                        )
                    ]
                )

            if not self.json_closed and self.function_end_token in tool_text:
                self.json_closed = True

                func_start = tool_text.find(self.tool_call_prefix) + len(
                    self.tool_call_prefix
                )
                func_content_end = tool_text.find(self.function_end_token, func_start)
                if func_content_end != -1:
                    func_content = tool_text[func_start:func_content_end]
                    try:
                        parsed_tool = self._parse_xml_function_call(
                            func_content,
                            self.streaming_request.tools
                            if self.streaming_request
                            else None,
                        )
                        if parsed_tool:
                            for i, tool in enumerate(self.prev_tool_call_arr):
                                if tool.get("name") == parsed_tool.function.name:
                                    self.prev_tool_call_arr[i][
                                        "arguments"
                                    ] = parsed_tool.function.arguments
                                    break
                    except Exception:
                        pass

                result = DeltaMessage(
                    tool_calls=[
                        DeltaToolCall(
                            index=self.current_tool_index,
                            function=DeltaFunctionCall(arguments="}"),
                        )
                    ]
                )

                self.in_function = False
                self.json_closed = True
                self.accumulated_params = {}
                return result

            param_starts = []
            idx = 0
            while True:
                idx = tool_text.find(self.parameter_prefix, idx)
                if idx == -1:
                    break
                param_starts.append(idx)
                idx += len(self.parameter_prefix)

            if (
                not self.in_param
                and self.param_count < len(param_starts)
                and len(param_starts) > self.param_count
            ):
                param_idx = param_starts[self.param_count]
                param_start = param_idx + len(self.parameter_prefix)
                remaining = tool_text[param_start:]

                if ">" in remaining:
                    name_end = remaining.find(">")
                    self.current_param_name = remaining[:name_end]

                    value_start = param_start + name_end + 1
                    value_text = tool_text[value_start:]
                    if value_text.startswith("\n"):
                        value_text = value_text[1:]

                    param_end_idx = value_text.find(self.parameter_end_token)
                    if param_end_idx == -1:
                        next_param_idx = value_text.find(self.parameter_prefix)
                        func_end_idx = value_text.find(self.function_end_token)

                        if next_param_idx != -1 and (
                            func_end_idx == -1 or next_param_idx < func_end_idx
                        ):
                            param_end_idx = next_param_idx
                        elif func_end_idx != -1:
                            param_end_idx = func_end_idx
                        else:
                            if current_block.complete:
                                param_end_idx = len(value_text)
                            else:
                                return None

                    if param_end_idx != -1:
                        param_value = value_text[:param_end_idx]
                        if param_value.endswith("\n"):
                            param_value = param_value[:-1]

                        self.accumulated_params[self.current_param_name] = param_value

                        param_config = self._get_arguments_config(
                            self.current_function_name or "",
                            self.streaming_request.tools
                            if self.streaming_request
                            else None,
                        )
                        converted_value = self._convert_param_value(
                            param_value,
                            self.current_param_name,
                            param_config,
                            self.current_function_name or "",
                        )
                        serialized_value = json.dumps(
                            converted_value,
                            ensure_ascii=False,
                        )

                        if self.param_count == 0:
                            json_fragment = (
                                f'"{self.current_param_name}": {serialized_value}'
                            )
                        else:
                            json_fragment = (
                                f', "{self.current_param_name}": {serialized_value}'
                            )

                        self.param_count += 1

                        return DeltaMessage(
                            tool_calls=[
                                DeltaToolCall(
                                    index=self.current_tool_index,
                                    function=DeltaFunctionCall(
                                        arguments=json_fragment
                                    ),
                                )
                            ]
                        )

        return None
