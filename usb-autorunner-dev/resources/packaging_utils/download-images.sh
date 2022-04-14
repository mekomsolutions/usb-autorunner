#!/usr/bin/env bash
mkdir -p $1
if [ -p /dev/stdin ]; then
        while IFS= read line; do
                skopeo sync --src docker --dest dir --scoped ${line} $1 --override-arch arm64 --override-os linux
        done
        if [ -d "$1/docker.io/library" ]; then
                # library repositories should be moved to the "docker.io" directory root
                mv $1/docker.io/library/* $1/docker.io
                rmdir $1/docker.io/library/
        fi

else
        echo "No input was found on stdin, skipping!"
        # Checking to ensure a filename was specified and that it exists
        if [ -f "$1" ]; then
                echo "Filename specified: ${1}"
                echo "Doing things now.."
        else
                echo "No input given!"
        fi
fi
