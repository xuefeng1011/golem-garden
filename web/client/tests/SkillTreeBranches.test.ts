import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import SkillTreeBranches from '@/components/hermes/souls/SkillTreeBranches.vue'
import type { SkillBranch } from '@/api/hermes/souls'

function makeBranch(partial: Partial<SkillBranch> = {}): SkillBranch {
  return {
    name: 'Vue',
    level: 3,
    demonstrated_count: 12,
    evidence: [],
    ...partial,
  }
}

describe('SkillTreeBranches', () => {
  it('renders branch name and demonstrated_count', () => {
    const wrapper = mount(SkillTreeBranches, {
      props: { branches: [makeBranch({ name: 'TypeScript', demonstrated_count: 7 })] },
    })
    expect(wrapper.find('.branch-name').text()).toBe('TypeScript')
    expect(wrapper.find('.branch-count').text()).toBe('7')
  })

  it('renders 5 dots with correct filled count for level 3', () => {
    const wrapper = mount(SkillTreeBranches, {
      props: { branches: [makeBranch({ level: 3 })] },
    })
    const dots = wrapper.findAll('.dot')
    expect(dots).toHaveLength(5)
    const filled = dots.filter((d) => d.classes().includes('filled'))
    expect(filled).toHaveLength(3)
  })

  it('renders all 5 dots filled for level 5', () => {
    const wrapper = mount(SkillTreeBranches, {
      props: { branches: [makeBranch({ level: 5 })] },
    })
    const filled = wrapper.findAll('.dot.filled')
    expect(filled).toHaveLength(5)
  })

  it('renders zero filled dots for level 0', () => {
    const wrapper = mount(SkillTreeBranches, {
      props: { branches: [makeBranch({ level: 0 })] },
    })
    const filled = wrapper.findAll('.dot.filled')
    expect(filled).toHaveLength(0)
  })

  it('renders multiple branches', () => {
    const wrapper = mount(SkillTreeBranches, {
      props: {
        branches: [
          makeBranch({ name: 'A', level: 1 }),
          makeBranch({ name: 'B', level: 4 }),
        ],
      },
    })
    const rows = wrapper.findAll('.branch-row')
    expect(rows).toHaveLength(2)
    expect(rows[0].find('.branch-name').text()).toBe('A')
    expect(rows[1].find('.branch-name').text()).toBe('B')
  })
})
