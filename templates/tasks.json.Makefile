{
    "version": "2.0.0",
    "command": "make",
	    "presentation": {
        "panel": "dedicated",
        "clear": true
    },
    "tasks": [
        {
            "label": "build",
            "group": {
                "kind": "build",
                "isDefault": true
            },
			"command": "make",
        },
        {
            "label": "test",
            "group": {
                "kind": "test",
                "isDefault": true
            }
        }
    ]
}

