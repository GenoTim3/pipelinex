import { Link } from 'react-router-dom'
import { formatDistanceToNow } from 'date-fns'
import { GitBranch, GitCommit, User, Clock } from 'lucide-react'
import StatusBadge from './StatusBadge'

function PipelineList({ runs, loading }) {
  if (loading) {
    return (
      <div className="space-y-4">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="bg-gray-800 rounded-lg p-4 animate-pulse">
            <div className="h-4 bg-gray-700 rounded w-1/4 mb-2"></div>
            <div className="h-3 bg-gray-700 rounded w-1/2"></div>
          </div>
        ))}
      </div>
    )
  }

  if (!runs || runs.length === 0) {
    return (
      <div className="bg-gray-800 rounded-lg p-8 text-center">
        <p className="text-gray-400">No pipeline runs yet.</p>
        <p className="text-gray-500 text-sm mt-2">
          Push to a repository with a .pipeline.yml file to trigger a run.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {runs.map((run) => (
        <Link
          key={run.id}
          to={`/runs/${run.id}`}
          className="block bg-gray-800 rounded-lg p-4 hover:bg-gray-750 transition-colors border border-gray-700 hover:border-gray-600"
        >
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center space-x-3">
              <StatusBadge status={run.status} />
              <span className="font-medium text-gray-200">
                {run.id.slice(0, 8)}
              </span>
            </div>
            <div className="flex items-center text-gray-400 text-sm">
              <Clock className="h-3.5 w-3.5 mr-1" />
              {formatDistanceToNow(new Date(run.created_at), { addSuffix: true })}
            </div>
          </div>
          
          <div className="flex items-center space-x-4 text-sm text-gray-400">
            <span className="flex items-center">
              <GitBranch className="h-3.5 w-3.5 mr-1" />
              {run.branch}
            </span>
            <span className="flex items-center">
              <GitCommit className="h-3.5 w-3.5 mr-1" />
              {run.commit_sha.slice(0, 7)}
            </span>
            {run.triggered_by && (
              <span className="flex items-center">
                <User className="h-3.5 w-3.5 mr-1" />
                {run.triggered_by}
              </span>
            )}
          </div>
          
          {run.steps && run.steps.length > 0 && (
            <div className="flex items-center space-x-1 mt-3">
              {run.steps.map((step, index) => (
                <div
                  key={index}
                  className={`h-1.5 flex-1 rounded-full ${
                    step.status === 'succeeded' ? 'bg-green-500' :
                    step.status === 'failed' ? 'bg-red-500' :
                    step.status === 'running' ? 'bg-blue-500 animate-pulse' :
                    'bg-gray-600'
                  }`}
                  title={`${step.name}: ${step.status}`}
                />
              ))}
            </div>
          )}
        </Link>
      ))}
    </div>
  )
}

export default PipelineList
