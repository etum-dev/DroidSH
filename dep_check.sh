#!/usr/bin/env bash

needed_tools=("git" "jq")

for uwu in "${needed_tools[@]}"
	do command -V $uwu
	if [[ $? -eq 1 ]] then
		echo "required command not found: $uwu"
		exit 1
	fi
done

