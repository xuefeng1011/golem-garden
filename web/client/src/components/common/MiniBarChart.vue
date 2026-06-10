<script setup lang="ts">
import { computed } from 'vue'

export interface BarDatum {
  label: string
  value: number
}

const props = withDefaults(
  defineProps<{
    data: BarDatum[]
    threshold?: number
    height?: number
  }>(),
  {
    height: 120,
  },
)

const PAD_TOP = 8

const maxValue = computed(() => {
  const values = props.data.map((d) => d.value)
  if (props.threshold !== undefined) values.push(props.threshold)
  const max = Math.max(0, ...values)
  return max > 0 ? max : 1
})

interface Bar extends BarDatum {
  x: string
  width: string
  y: number
  barHeight: number
  exceeds: boolean
}

const bars = computed<Bar[]>(() => {
  const n = props.data.length
  if (n === 0) return []
  const slot = 100 / n
  const barWidth = slot * 0.64
  const usable = props.height - PAD_TOP
  return props.data.map((d, i) => {
    const barHeight = Math.max(
      d.value > 0 ? 2 : 0,
      Math.round((d.value / maxValue.value) * usable),
    )
    return {
      ...d,
      x: `${(i * slot + (slot - barWidth) / 2).toFixed(2)}%`,
      width: `${barWidth.toFixed(2)}%`,
      y: props.height - barHeight,
      barHeight,
      exceeds: props.threshold !== undefined && d.value > props.threshold,
    }
  })
})

const thresholdY = computed(() => {
  if (props.threshold === undefined) return null
  const usable = props.height - PAD_TOP
  return props.height - (props.threshold / maxValue.value) * usable
})
</script>

<template>
  <div class="mini-bar-chart">
    <svg :height="height" width="100%" role="img">
      <rect
        v-for="bar in bars"
        :key="bar.label"
        class="bar"
        :class="{ 'bar-warn': bar.exceeds }"
        :x="bar.x"
        :y="bar.y"
        :width="bar.width"
        :height="bar.barHeight"
        rx="2"
      >
        <title>{{ bar.label }}: {{ bar.value }}</title>
      </rect>
      <line
        v-if="thresholdY !== null"
        class="threshold-line"
        x1="0"
        x2="100%"
        :y1="thresholdY"
        :y2="thresholdY"
      />
    </svg>
    <div class="labels">
      <span
        v-for="bar in bars"
        :key="bar.label"
        class="label"
        :title="bar.label"
      >
        {{ bar.label }}
      </span>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.mini-bar-chart {
  width: 100%;

  svg {
    display: block;
  }
}

.bar {
  fill: rgba(var(--accent-primary-rgb), 0.75);
  transition: fill $transition-fast;

  &:hover {
    fill: $accent-primary;
  }

  &.bar-warn {
    fill: rgba(var(--warning-rgb), 0.85);

    &:hover {
      fill: $warning;
    }
  }
}

.threshold-line {
  stroke: $warning;
  stroke-width: 1;
  stroke-dasharray: 4 3;
  opacity: 0.7;
}

.labels {
  display: flex;
  margin-top: 4px;

  .label {
    flex: 1;
    text-align: center;
    font-size: 10px;
    color: $text-muted;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    padding: 0 2px;
  }
}
</style>
