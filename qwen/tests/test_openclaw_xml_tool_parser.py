import json
import sys
from pathlib import Path

from vllm.entrypoints.openai.chat_completion.protocol import ChatCompletionRequest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tool_parsers.openclaw_xml_tool_parser import OpenClawXMLToolParser


class DummyTokenizer:
    def get_vocab(self):
        return {
            "<tool_call>": 1,
            "</tool_call>": 2,
        }


def make_request():
    return ChatCompletionRequest(
        model="Qwen3.5-27B",
        messages=[{"role": "user", "content": "查看当前目录文件"}],
        stream=True,
        tools=[
            {
                "type": "function",
                "function": {
                    "name": "exec",
                    "description": "Run a shell command",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {"type": "string"},
                            "description": {"type": "string"},
                        },
                        "required": ["command"],
                    },
                },
            }
        ],
        tool_choice="auto",
    )


def test_extract_tool_calls_accepts_bare_function_block():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()
    model_output = (
        "先执行工具\n"
        "<function=exec>\n"
        "<parameter=command>\nls -la\n</parameter>\n"
        "<parameter=description>\n列出文件\n</parameter>\n"
        "</function>"
    )

    result = parser.extract_tool_calls(model_output, request)

    assert result.tools_called is True
    assert result.content == "先执行工具\n"
    assert len(result.tool_calls) == 1
    assert result.tool_calls[0].function.name == "exec"
    assert json.loads(result.tool_calls[0].function.arguments) == {
        "command": "ls -la",
        "description": "列出文件",
    }


def test_streaming_detects_bare_function_block_without_tool_wrapper():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()
    delta_text = (
        "<function=exec>\n"
        "<parameter=command>\nls -la\n</parameter>\n"
        "<parameter=description>\n列出文件\n</parameter>\n"
        "</function>"
    )

    first = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text=delta_text,
        delta_text=delta_text,
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert first is not None
    assert first.tool_calls is not None
    assert first.tool_calls[0].function.name == "exec"
    assert json.loads(parser.prev_tool_call_arr[0]["arguments"]) == {
        "command": "ls -la",
        "description": "列出文件",
    }

    final = parser.extract_tool_calls_streaming(
        previous_text=delta_text,
        current_text=delta_text,
        delta_text="",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[999],
        request=request,
    )

    assert final is not None
    assert final.content == ""


def test_streaming_holds_partial_function_prefix_until_tool_call_is_confirmed():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()

    first = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text="<function",
        delta_text="<function",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert first is None

    second_text = (
        "<function=exec>\n"
        "<parameter=command>\nls -la\n</parameter>\n"
        "</function>"
    )
    second = parser.extract_tool_calls_streaming(
        previous_text="<function",
        current_text=second_text,
        delta_text=second_text[len("<function"):],
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert second is not None
    assert second.content is None
    assert second.tool_calls is not None
    assert second.tool_calls[0].function.name == "exec"


def test_extract_tool_calls_keeps_plain_content_without_tool_call():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()
    model_output = "正常说明\n<tool_code>grep docs</tool_code>\n</tool_call>\n最终结论"

    result = parser.extract_tool_calls(model_output, request)

    assert result.tools_called is False
    assert result.tool_calls == []
    assert result.content == model_output


def test_streaming_swallows_split_closing_tag_and_keeps_following_text():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()

    first = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text="</param",
        delta_text="</param",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert first is None

    second = parser.extract_tool_calls_streaming(
        previous_text="</param",
        current_text="</parameter>Hello",
        delta_text="eter>Hello",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert second is not None
    assert second.content == "Hello"


def test_streaming_swallows_trailing_closing_tag_tail_chunk():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()

    first = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text="没问题，hotwa。有什么我可以帮你的吗？",
        delta_text="没问题，hotwa。有什么我可以帮你的吗？",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert first is not None
    assert first.content == "没问题，hotwa。有什么我可以帮你的吗？"

    second = parser.extract_tool_calls_streaming(
        previous_text="没问题，hotwa。有什么我可以帮你的吗？",
        current_text="没问题，hotwa。有什么我可以帮你的吗？</parameter></function>",
        delta_text="</parameter></function>",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert second is None


def test_streaming_preserves_spaces_between_text_chunks():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()

    first = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text="Alright, I can",
        delta_text="Alright, I can",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert first is not None
    assert first.content == "Alright, I can"

    second = parser.extract_tool_calls_streaming(
        previous_text="Alright, I can",
        current_text="Alright, I can see this is a new session.",
        delta_text=" see this is a new session.",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert second is not None
    assert second.content == " see this is a new session."


def test_streaming_bare_exec_waits_for_complete_required_command_parameter():
    parser = OpenClawXMLToolParser(DummyTokenizer())
    request = make_request()

    partial = parser.extract_tool_calls_streaming(
        previous_text="",
        current_text="<function=exec>\n<parameter=command>\nls",
        delta_text="<function=exec>\n<parameter=command>\nls",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert partial is None

    completed_text = (
        "<function=exec>\n"
        "<parameter=command>\nls -la\n</parameter>\n"
        "</function>"
    )
    completed = parser.extract_tool_calls_streaming(
        previous_text="<function=exec>\n<parameter=command>\nls",
        current_text=completed_text,
        delta_text=" -la\n</parameter>\n</function>",
        previous_token_ids=[],
        current_token_ids=[],
        delta_token_ids=[],
        request=request,
    )

    assert completed is not None
    assert completed.tool_calls is not None
    assert completed.tool_calls[0].function.name == "exec"
