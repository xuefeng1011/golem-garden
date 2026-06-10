---
project: (피지컬 AI 프로젝트명)
type: physical-ai
created: 2026-06-10
updated: 2026-06-10
---

# Forge Board — 피지컬 AI (IoT·AIoT·로보틱스)

## 팀 구성

| SOUL | 역할 | OMC Agent | 모델 | Rank | 상태 |
|------|------|-----------|------|------|------|
| Nex | Director | architect | opus | junior | active |
| Ember | 임베디드/IoT 펌웨어 | executor | sonnet | novice | active |
| Neura | 엣지 AI/AIoT | scientist | sonnet | novice | active |
| Gopher | Go 백엔드/플릿 | executor | sonnet | novice | active |
| Atlas | 로보틱스/제어 | architect | opus | novice | active |

## 기술스택
- Firmware: C/C++, FreeRTOS/Zephyr, ESP-IDF
- Edge AI: TFLite Micro, ONNX Runtime, Python
- Backend: Go, gRPC, MQTT, InfluxDB
- Robotics: ROS2, Gazebo/Isaac Sim

## forge 실행 모드 설정

| 작업 유형 | 실행 모드 | 설명 |
|----------|----------|------|
| 디바이스→클라우드 기능 | forge build | Ember+Gopher 병렬 (펌웨어/백엔드 동시) |
| 온디바이스 모델 배포 | forge build | Neura 모델 → Ember 통합 순차 |
| 단일 펌웨어 수정 | forge quick | Ember 단독 |
| 제어/안전 설계 리뷰 | forge review atlas | Atlas가 안전 관점 크로스 리뷰 |
| 백엔드 API 단독 | forge assign gopher | Gopher 단독 |
