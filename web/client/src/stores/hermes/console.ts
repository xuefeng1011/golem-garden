import { defineStore } from 'pinia'
import { ref } from 'vue'
import { fetchConsole, type ConsoleData, type RunMeta } from '@/api/hermes/console'
import { fetchTrace, type TraceResponse } from '@/api/hermes/traces'
import { ApiError } from '@/utils/api-error'

const POLL_INTERVAL_MS = 10_000

export const useConsoleStore = defineStore('console', () => {
  // ── console state ──────────────────────────────────────────────────────────
  const data = ref<ConsoleData | null>(null)
  const loading = ref(false)
  const loadError = ref<ApiError | null>(null)

  // ── trace state ────────────────────────────────────────────────────────────
  const selectedRun = ref<RunMeta | null>(null)
  const traceData = ref<TraceResponse | null>(null)
  const traceLoading = ref(false)
  const traceError = ref<ApiError | null>(null)
  const traceAppending = ref(false)

  // ── poll internals ─────────────────────────────────────────────────────────
  let pollTimer: ReturnType<typeof setInterval> | null = null
  let currentProjectId: string | null = null

  async function fetchData(projectId: string) {
    loading.value = true
    loadError.value = null
    try {
      data.value = await fetchConsole(projectId)
    } catch (e) {
      loadError.value = e instanceof ApiError
        ? e
        : new ApiError(String(e), null, 'client')
    } finally {
      loading.value = false
    }
  }

  function startPolling(projectId: string) {
    if (pollTimer && currentProjectId === projectId) return
    stopPolling()
    currentProjectId = projectId
    fetchData(projectId)
    pollTimer = setInterval(() => fetchData(projectId), POLL_INTERVAL_MS)
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer)
      pollTimer = null
    }
    currentProjectId = null
  }

  // ── trace fetch (lazy, 1-shot per run selection) ───────────────────────────
  async function selectRun(run: RunMeta, projectId: string) {
    selectedRun.value = run
    traceData.value = null
    traceError.value = null
    traceLoading.value = true
    try {
      traceData.value = await fetchTrace(projectId, run.run_id)
    } catch (e) {
      traceError.value = e instanceof ApiError
        ? e
        : new ApiError(String(e), null, 'client')
    } finally {
      traceLoading.value = false
    }
  }

  async function loadMoreTrace(projectId: string) {
    if (!selectedRun.value || !traceData.value) return
    if (traceAppending.value) return
    const nextOffset = traceData.value.offset + traceData.value.lines.length
    if (nextOffset >= traceData.value.total_lines) return
    traceAppending.value = true
    try {
      const more = await fetchTrace(projectId, selectedRun.value.run_id, nextOffset)
      traceData.value = {
        ...more,
        lines: [...traceData.value.lines, ...more.lines],
      }
    } catch {
      // non-fatal — user can retry
    } finally {
      traceAppending.value = false
    }
  }

  function closeRun() {
    selectedRun.value = null
    traceData.value = null
    traceError.value = null
  }

  return {
    data,
    loading,
    loadError,
    selectedRun,
    traceData,
    traceLoading,
    traceError,
    traceAppending,
    startPolling,
    stopPolling,
    selectRun,
    loadMoreTrace,
    closeRun,
  }
})
