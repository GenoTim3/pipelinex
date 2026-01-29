import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  timeout: 10000,
})

export const getPipelineRuns = async (limit = 20, offset = 0) => {
  const response = await api.get(`/pipelines/runs?limit=${limit}&offset=${offset}`)
  return response.data
}

export const getPipelineRun = async (runId) => {
  const response = await api.get(`/pipelines/runs/${runId}`)
  return response.data
}

export const getRunStatus = async (runId) => {
  const response = await api.get(`/pipelines/runs/${runId}/status`)
  return response.data
}

export const getRunLogs = async (runId) => {
  const response = await api.get(`/pipelines/runs/${runId}/logs`)
  return response.data
}

export const getRepositories = async () => {
  const response = await api.get('/pipelines/repositories')
  return response.data
}

export const getStats = async () => {
  const response = await api.get('/pipelines/stats')
  return response.data
}

export const getHealthStatus = async () => {
  const response = await axios.get('/health/all')
  return response.data
}

export default api
