// Chemistry API module — GET /v1/projects/{id}/chemistry
// The fetcher and types are shared with meta.ts (Growth & Chemistry view);
// re-exported here so team-related code has a dedicated, stable module path.
export type { ChemistryPair, ChemistryEvent, ChemistryData } from './meta'
export { fetchChemistry } from './meta'
