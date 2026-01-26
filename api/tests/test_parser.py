"""Tests for pipeline parser."""

import pytest
from api.src.services.pipeline_parser import (
    parse_pipeline_config,
    parse_pipeline_dict,
    PipelineConfigError,
)

def test_valid_pipeline():
    config = """
name: Test Pipeline
steps:
  - name: Build
    image: node:18
    commands:
      - npm install
      - npm run build
  - name: Test
    image: node:18
    commands:
      - npm test
"""
    result = parse_pipeline_config(config)
    assert result["name"] == "Test Pipeline"
    assert len(result["steps"]) == 2
    assert result["steps"][0]["name"] == "Build"
    assert result["steps"][1]["image"] == "node:18"

def test_missing_steps():
    config = """
name: Bad Pipeline
"""
    with pytest.raises(PipelineConfigError, match="must have 'steps'"):
        parse_pipeline_config(config)

def test_missing_step_name():
    config = """
name: Bad Pipeline
steps:
  - image: node:18
    commands:
      - npm install
"""
    with pytest.raises(PipelineConfigError, match="missing 'name'"):
        parse_pipeline_config(config)

def test_missing_step_image():
    config = """
name: Bad Pipeline
steps:
  - name: Build
    commands:
      - npm install
"""
    with pytest.raises(PipelineConfigError, match="missing 'image'"):
        parse_pipeline_config(config)

def test_empty_config():
    with pytest.raises(PipelineConfigError, match="Empty"):
        parse_pipeline_config("")

def test_dict_parsing():
    config = {
        "name": "Dict Pipeline",
        "steps": [
            {"name": "Step 1", "image": "alpine", "commands": ["echo hello"]}
        ]
    }
    result = parse_pipeline_dict(config)
    assert result["name"] == "Dict Pipeline"
    assert len(result["steps"]) == 1
