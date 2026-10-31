#!/bin/bash
# ApplicationStop — 앱 중지 (서버는 이미 로드 밸런서에서 빠진 상태)
systemctl stop app || true
