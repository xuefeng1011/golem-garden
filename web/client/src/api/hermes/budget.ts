import { request } from '../client'

export interface BudgetSoulEntry {
  soul: string
  cost_usd: number
  tasks: number
}

export interface BudgetDailyEntry {
  date: string
  cost_usd: number
}

export interface ProjectBudget {
  total_cost_usd: number
  by_soul: BudgetSoulEntry[]
  daily: BudgetDailyEntry[]
  budget_limit_usd: number | null
  warning: string | null
}

export async function fetchBudget(projectId: string): Promise<ProjectBudget> {
  return request<ProjectBudget>(
    `/v1/projects/${encodeURIComponent(projectId)}/budget`
  )
}
