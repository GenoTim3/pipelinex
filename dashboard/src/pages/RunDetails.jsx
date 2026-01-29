import { useState, useEffect } from 'react'
import { useParams, Link } from 'react-router-dom'
import { ArrowLeft, RefreshCw } from 'lucide-react'
import PipelineRun from '../components/PipelineRun'
import { getPipelineRun, getRunLogs } from '../services/api'

function RunDetails() {
  const { runId } = useParams()
  const [run, setRun] = useState(null)
  const [logs, setLogs] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetchData = async () => {
    try {
      const [runData, logsData] = await Promise.all([
        getPipelineRun(runId),
        getRunLogs(runId).catch(() => null),
      ])
      setRun(runData)
      setLogs(logsData)
      setError(null)
    } catch (err) {
      setError('Failed to load pipeline run')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
    
    // Auto-refresh if running
    const interval = setInterval(() => {
      if (run?.status === 'running' || run?.status === 'queued') {
        fetchData()
      }
    }, 3000)
    
    return () => clearInterval(interval)
  }, [runId, run?.status])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="h-8 w-8 animate-spin text-gray-400" />
      </div>
    )
  }

  if (error || !run) {
    return (
      <div className="bg-red-500/10 border border-red-500 rounded-lg p-6 text-center">
        <p className="text-red-400">{error || 'Pipeline run not found'}</p>
        <Link
          to="/"
          className="inline-flex items-center mt-4 text-sm text-gray-400 hover:text-white"
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          Back to Dashboard
        </Link>
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-4">
          <Link
            to="/"
            className="flex items-center text-gray-400 hover:text-white transition-colors"
          >
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <h1 className="text-2xl font-bold">
            Run {runId.slice(0, 8)}
          </h1>
        </div>
        <button
          onClick={fetchData}
          className="flex items-center space-x-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 rounded-md text-sm transition-colors"
        >
          <RefreshCw className="h-4 w-4" />
          <span>Refresh</span>
        </button>
      </div>

      <PipelineRun run={run} logs={logs} />
    </div>
  )
}

export default RunDetails
