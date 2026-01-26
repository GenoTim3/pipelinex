"""
Pipeline YAML parser.
Implementation in Phase 2.
"""

import yaml
from typing import List, Dict, Any

def parse_pipeline_config(yaml_content: str) -> Dict[str, Any]:
    """Parse pipeline YAML configuration."""
    config = yaml.safe_load(yaml_content)
    return validate_config(config)

def validate_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """Validate pipeline configuration structure."""
    if not config:
        raise ValueError("Empty pipeline configuration")
    
    if "steps" not in config:
        raise ValueError("Pipeline must have 'steps' defined")
    
    for i, step in enumerate(config["steps"]):
        if "name" not in step:
            raise ValueError(f"Step {i} missing 'name'")
        if "image" not in step:
            raise ValueError(f"Step {i} missing 'image'")
        if "commands" not in step:
            raise ValueError(f"Step {i} missing 'commands'")
    
    return config
