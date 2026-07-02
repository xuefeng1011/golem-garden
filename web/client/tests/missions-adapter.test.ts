import { describe, expect, it } from 'vitest'
import { adaptMission, type RawMission } from '@/api/hermes/missions'

function raw(overrides: Partial<RawMission> = {}): RawMission {
  return {
    id: 'msn_1_1',
    goal: 'test goal',
    status: 'active',
    created: '2026-07-03T00:00:00',
    tasks: [
      { idx: 0, task: 't0', soul: 'ryn', status: 'done' },
      { idx: 1, task: 't1', soul: '', status: 'failed' },
      { idx: 2, task: 't2', soul: 'zen', status: 'in_progress' },
    ],
    ...overrides,
  }
}

describe('missions adapter — bash enum → UI enum 정합 (단일 매핑 지점)', () => {
  it('mission: active → running', () => {
    expect(adaptMission(raw()).status).toBe('running')
  })

  it('mission: completed/failed 는 그대로', () => {
    expect(adaptMission(raw({ status: 'completed' })).status).toBe('completed')
    expect(adaptMission(raw({ status: 'failed' })).status).toBe('failed')
  })

  it('mission: 미지의 상태는 pending 폴백 (크래시 방지)', () => {
    expect(adaptMission(raw({ status: 'weird' })).status).toBe('pending')
  })

  it('task: failed → error, 나머지는 그대로', () => {
    const m = adaptMission(raw())
    expect(m.tasks.map((t) => t.status)).toEqual(['done', 'error', 'in_progress'])
  })

  it('task: 미지의 상태는 pending 폴백', () => {
    const m = adaptMission(
      raw({ tasks: [{ idx: 0, task: 't', soul: '', status: 'exploded' }] }),
    )
    expect(m.tasks[0].status).toBe('pending')
  })
})
