import { useState, useEffect } from 'react'
import { RefreshCw, Activity, CheckCircle, XCircle, Clock } from 'lucide-react'
import PipelineList from '../components/PipelineList'
import { getPipelineRuns, getStats, getHealthStatus } from '../services/api'

function StatCard({ icon: Icon, label, value, color }) {
  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-gray-400 text-sm">{label}</p>
          <p className="text-2xl font-bold mt-1">{value}</p>
        </div>
        <Icon className={`h-8 w-8 ${color}`} />
      </div>
    </div>
  )
}

function Home() {
  const [runs, setRuns] = useState([])
  const [stats, setStats] = useState(null)
  const [health, setHealth] = useState(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const fetchData = async () => {
    try {
      const [runsData, statsData, healthData] = await Promise.all([
        getPipelineRuns(),
        getStats(),
        getHealthStatus(),
      ])
      setRuns(runsData)
      setStats(statsData)
      setHealth(healthData)
    } catch (error) {
      console.error('Failed to fetch data:', error)
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 10000) // Refresh every 10s
    return () => clearInterval(interval)
  }, [])

  const handleRefresh = () => {
    setRefreshing(true)
    fetchData()
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <div className="flex items-center space-x-4">
          {health && (
            <span className={`flex items-center text-sm ${
              health.status === 'healthy' ? 'text-green-400' : 'text-yellow-400'
            }`}>
              <span className={`h-2 w-2 rounded-full mr-2 ${
                health.status === 'healthy' ? 'bg-green-400' : 'bg-yellow-400'
              }`} />
              System {health.status}
            </span>
          )}
          <button
            onClick={handleRefresh}
            disabled={refreshing}
            className="flex items-center space-x-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 rounded-md text-sm transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <StatCard
          icon={Activity}
          label="Total Runs"
          value={stats?.total_runs || 0}
          color="text-blue-400"
        />
        <StatCard
          icon={CheckCircle}
          label="Succeeded"
          value={stats?.runs?.succeeded || 0}
          color="text-green-400"
        />
        <StatCard
          icon={XCircle}
          label="Failed"
          value={stats?.runs?.failed || 0}
          color="text-red-400"
        />
        <StatCard
          icon={Clock}
          label="Queued"
          value={(stats?.runs?.queued || 0) + (stats?.runs?.pending || 0) + (stats?.runs?.running || 0)}
          color="text-yellow-400"
        />
      </div>

      <h2 className="text-xl font-semibold mb-4">Recent Pipeline Runs</h2>
      <PipelineList runs={runs} loading={loading} />
    </div>
  )
}

export default Home
