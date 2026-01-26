"""
Pipeline YAML parser and validator.
"""

import yaml
from typing import List, Dict, Any, Optional

class PipelineConfigError(Exception):
    """Raised when pipeline configuration is invalid."""
    pass

def parse_pipeline_config(yaml_content: str) -> Dict[str, Any]:
    """Parse pipeline YAML configuration from string."""
    try:
        config = yaml.safe_load(yaml_content)
    except yaml.YAMLError as e:
        raise PipelineConfigError(f"Invalid YAML: {e}")
    
    return validate_config(config)

def parse_pipeline_dict(config: Dict[str, Any]) -> Dict[str, Any]:
    """Validate pipeline configuration from dict."""
    return validate_config(config)

def validate_config(config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Validate pipeline configuration structure."""
    if not config:
        raise PipelineConfigError("Empty pipeline configuration")
    
    if not isinstance(config, dict):
        raise PipelineConfigError("Pipeline configuration must be a dictionary")
    
    # Validate name (optional but recommended)
    name = config.get("name", "Unnamed Pipeline")
    if not isinstance(name, str):
        raise PipelineConfigError("Pipeline 'name' must be a string")
    
    # Validate steps
    if "steps" not in config:
        raise PipelineConfigError("Pipeline must have 'steps' defined")
    
    steps = config["steps"]
    if not isinstance(steps, list):
        raise PipelineConfigError("Pipeline 'steps' must be a list")
    
    if len(steps) == 0:
        raise PipelineConfigError("Pipeline must have at least one step")
    
    validated_steps = []
    for i, step in enumerate(steps):
        validated_step = validate_step(step, i)
        validated_steps.append(validated_step)
    
    return {
        "name": name,
        "steps": validated_steps,
        "env": config.get("env", {}),
    }

def validate_step(step: Dict[str, Any], index: int) -> Dict[str, Any]:
    """Validate a single pipeline step."""
    if not isinstance(step, dict):
        raise PipelineConfigError(f"Step {index} must be a dictionary")
    
    # Required fields
    if "name" not in step:
        raise PipelineConfigError(f"Step {index} missing 'name'")
    
    if "image" not in step:
        raise PipelineConfigError(f"Step {index} missing 'image'")
    
    if "commands" not in step:
        raise PipelineConfigError(f"Step {index} missing 'commands'")
    
    # Validate types
    if not isinstance(step["name"], str):
        raise PipelineConfigError(f"Step {index} 'name' must be a string")
    
    if not isinstance(step["image"], str):
        raise PipelineConfigError(f"Step {index} 'image' must be a string")
    
    if not isinstance(step["commands"], list):
        raise PipelineConfigError(f"Step {index} 'commands' must be a list")
    
    for j, cmd in enumerate(step["commands"]):
        if not isinstance(cmd, str):
            raise PipelineConfigError(f"Step {index} command {j} must be a string")
    
    return {
        "name": step["name"],
        "image": step["image"],
        "commands": step["commands"],
        "env": step.get("env", {}),
        "timeout": step.get("timeout", 600),  # Default 10 min timeout
    }
