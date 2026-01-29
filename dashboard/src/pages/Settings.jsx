import { useState, useEffect } from 'react'
import { CheckCircle, XCircle, RefreshCw } from 'lucide-react'
import { getHealthStatus, getRepositories } from '../services/api'

function HealthIndicator({ status, label }) {
  const isHealthy = status === 'healthy' || status === 'connected'
  
  return (
    <div className="flex items-center justify-between py-3 border-b border-gray-700 last:border-0">
      <span className="text-gray-300">{label}</span>
      <span className={`flex items-center ${isHealthy ? 'text-green-400' : 'text-red-400'}`}>
        {isHealthy ? (
          <CheckCircle className="h-4 w-4 mr-1" />
        ) : (
          <XCircle className="h-4 w-4 mr-1" />
        )}
        {status}
      </span>
    </div>
  )
}

function Settings() {
  const [health, setHealth] = useState(null)
  const [repos, setRepos] = useState([])
  const [loading, setLoading] = useState(true)

  const fetchData = async () => {
    try {
      const [healthData, reposData] = await Promise.all([
        getHealthStatus(),
        getRepositories(),
      ])
      setHealth(healthData)
      setRepos(reposData)
    } catch (error) {
      console.error('Failed to fetch settings data:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="h-8 w-8 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 className="text-lg font-semibold mb-4">System Health</h2>
          {health?.services && (
            <div>
              <HealthIndicator status={health.services.api} label="API" />
              <HealthIndicator status={health.services.database} label="Database" />
              <HealthIndicator status={health.services.redis} label="Redis" />
            </div>
          )}
          <div className="mt-4 pt-4 border-t border-gray-700">
            <div className="flex items-center justify-between">
              <span className="text-gray-400">Queue Length</span>
              <span className="font-mono">{health?.services?.queue_length || 0}</span>
            </div>
          </div>
        </div>

        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 className="text-lg font-semibold mb-4">Registered Repositories</h2>
          {repos.length === 0 ? (
            <p className="text-gray-400 text-sm">
              No repositories registered yet. Push to a repo with a .pipeline.yml file to register it.
            </p>
          ) : (
            <div className="space-y-2">
              {repos.map((repo) => (
                <div
                  key={repo.id}
                  className="flex items-center justify-between py-2 border-b border-gray-700 last:border-0"
                >
                  <span className="font-mono text-sm">{repo.full_name}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="mt-6 bg-gray-800 rounded-lg p-6 border border-gray-700">
        <h2 className="text-lg font-semibold mb-4">Webhook Configuration</h2>
        <p className="text-gray-400 text-sm mb-4">
          Configure your GitHub repository to send webhooks to PipelineX.
        </p>
        <div className="bg-gray-900 rounded p-4">
          <p className="text-sm text-gray-400 mb-1">Webhook URL</p>
          <code className="text-green-400">
            http://your-server:8000/api/webhooks/github
          </code>
        </div>
        <div className="mt-4 text-sm text-gray-400">
          <p>1. Go to your repository Settings → Webhooks</p>
          <p>2. Add the webhook URL above</p>
          <p>3. Set content type to <code className="text-gray-300">application/json</code></p>
          <p>4. Select "Just the push event"</p>
        </div>
      </div>
    </div>
  )
}

export default Settings
