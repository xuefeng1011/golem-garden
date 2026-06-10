import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import MiniBarChart from '@/components/common/MiniBarChart.vue'

const sampleData = [
  { label: 'Mon', value: 3 },
  { label: 'Tue', value: 8 },
  { label: 'Wed', value: 5 },
]

describe('MiniBarChart', () => {
  it('renders one bar per datum', () => {
    const wrapper = mount(MiniBarChart, { props: { data: sampleData } })
    expect(wrapper.findAll('rect.bar')).toHaveLength(3)
  })

  it('renders labels under the chart', () => {
    const wrapper = mount(MiniBarChart, { props: { data: sampleData } })
    const labels = wrapper.findAll('.label').map((l) => l.text())
    expect(labels).toEqual(['Mon', 'Tue', 'Wed'])
  })

  it('exposes value tooltips via svg title', () => {
    const wrapper = mount(MiniBarChart, { props: { data: sampleData } })
    expect(wrapper.findAll('rect.bar title')[1].text()).toBe('Tue: 8')
  })

  it('marks bars exceeding the threshold with warning class', () => {
    const wrapper = mount(MiniBarChart, {
      props: { data: sampleData, threshold: 6 },
    })
    const bars = wrapper.findAll('rect.bar')
    expect(bars[0].classes()).not.toContain('bar-warn')
    expect(bars[1].classes()).toContain('bar-warn')
    expect(bars[2].classes()).not.toContain('bar-warn')
  })

  it('renders a threshold line only when threshold is set', () => {
    const withThreshold = mount(MiniBarChart, {
      props: { data: sampleData, threshold: 6 },
    })
    expect(withThreshold.find('line.threshold-line').exists()).toBe(true)

    const without = mount(MiniBarChart, { props: { data: sampleData } })
    expect(without.find('line.threshold-line').exists()).toBe(false)
  })

  it('uses default height of 120 and accepts custom height', () => {
    const wrapper = mount(MiniBarChart, { props: { data: sampleData } })
    expect(wrapper.find('svg').attributes('height')).toBe('120')

    const tall = mount(MiniBarChart, {
      props: { data: sampleData, height: 200 },
    })
    expect(tall.find('svg').attributes('height')).toBe('200')
  })

  it('renders no bars for empty data', () => {
    const wrapper = mount(MiniBarChart, { props: { data: [] } })
    expect(wrapper.findAll('rect.bar')).toHaveLength(0)
  })

  it('scales the tallest bar to fill the usable height', () => {
    const wrapper = mount(MiniBarChart, { props: { data: sampleData } })
    const tallest = wrapper.findAll('rect.bar')[1]
    // height 120, pad 8 -> max bar height 112, y = 120 - 112 = 8
    expect(tallest.attributes('height')).toBe('112')
    expect(tallest.attributes('y')).toBe('8')
  })
})
