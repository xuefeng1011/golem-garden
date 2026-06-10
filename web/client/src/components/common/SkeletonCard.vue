<script setup lang="ts">
withDefaults(
  defineProps<{
    rows?: number
    showAvatar?: boolean
  }>(),
  {
    rows: 3,
    showAvatar: false,
  },
)
</script>

<template>
  <div class="skeleton-card" aria-busy="true">
    <div v-if="showAvatar" class="skeleton-header">
      <div class="shimmer skeleton-avatar" />
      <div class="shimmer skeleton-line skeleton-title" />
    </div>
    <div
      v-for="i in rows"
      :key="i"
      class="shimmer skeleton-line"
      :class="{ 'skeleton-line-last': i === rows }"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.skeleton-card {
  background-color: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.skeleton-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 4px;

  .skeleton-title {
    flex: 1;
    max-width: 40%;
    height: 14px;
  }
}

.skeleton-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  flex-shrink: 0;
}

.skeleton-line {
  height: 12px;
  border-radius: $radius-sm;
  width: 100%;

  &.skeleton-line-last {
    width: 60%;
  }
}

.shimmer {
  background: linear-gradient(
    90deg,
    rgba(var(--text-muted-rgb), 0.12) 25%,
    rgba(var(--text-muted-rgb), 0.22) 50%,
    rgba(var(--text-muted-rgb), 0.12) 75%
  );
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.4s var(--ease-in-out) infinite;
}

@keyframes skeleton-shimmer {
  0% {
    background-position: 200% 0;
  }
  100% {
    background-position: -200% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .shimmer {
    animation: none;
  }
}
</style>
