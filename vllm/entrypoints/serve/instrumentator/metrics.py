# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright contributors to the vLLM project


import logging
import prometheus_client
import regex as re
from fastapi import FastAPI, Response
from prometheus_client import make_asgi_app
from starlette.routing import Mount

from vllm.v1.metrics.prometheus import get_prometheus_registry

logger = logging.getLogger(__name__)


class PrometheusResponse(Response):
    media_type = prometheus_client.CONTENT_TYPE_LATEST


def attach_router(app: FastAPI):
    """Mount prometheus metrics to a FastAPI app."""

    registry = get_prometheus_registry()

    # Try to set up prometheus_fastapi_instrumentator
    # This may fail with some FastAPI/Starlette versions due to
    # '_IncludedRouter' object has no attribute 'path' error
    try:
        from prometheus_fastapi_instrumentator import Instrumentator
        # `response_class=PrometheusResponse` is needed to return an HTTP
        # response with header "Content-Type: text/plain; version=0.0.4;
        # charset=utf-8" instead of the default "application/json" which
        # is incorrect.
        # See https://github.com/trallnag/prometheus-fastapi-instrumentator/issues/163#issue-1296092364
        Instrumentator(
            excluded_handlers=[
                "/metrics",
                "/health",
                "/load",
                "/ping",
                "/version",
                "/server_info",
            ],
            registry=registry,
        ).add().instrument(app).expose(app, response_class=PrometheusResponse)
    except Exception as e:
        logger.warning("Failed to setup prometheus_fastapi_instrumentator: %s",
                       e)

    # Add prometheus asgi middleware to route /metrics requests
    metrics_route = Mount("/metrics", make_asgi_app(registry=registry))

    # Workaround for 307 Redirect for /metrics
    metrics_route.path_regex = re.compile("^/metrics(?P<path>.*)$")
    app.routes.append(metrics_route)
