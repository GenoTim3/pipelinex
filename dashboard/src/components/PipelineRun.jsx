import { useState } from 'react'
import { formatDistanceToNow, format } from 'date-fns'
import { ChevronDown, ChevronRight, Terminal } from 'lucide-react'
import StatusBadge from './StatusBadge'

function StepCard({ step, isExpanded, onToggle }) {
  return (
    <div className="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between p-4 hover:bg-gray-750 transition-colors"
      >
        <div className="flex items-center space-x-3">
          {isExpanded ? (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronRight className="h-4 w-4 text-gray-400" />
          )}
          <StatusBadge status={step.status} size="sm" />
          <span className="font-medium">{step.name}</span>
        </div>
        <div className="flex items-center space-x-4 text-sm text-gray-400">
          <span className="text-gray-500">{step.image}</span>
          {step.started_at && step.finished_at && (
            <span>
              {Math.round(
                (new Date(step.finished_at) - new Date(step.started_at)) / 1000
              )}s
            </span>
          )}
        </div>
      </button>
      
      {isExpanded && (
        <div className="border-t border-gray-700">
          <div className="p-4 bg-gray-850">
            <div className="flex items-center space-x-2 text-sm text-gray-400 mb-2">
              <Terminal className="h-4 w-4" />
              <span>Commands</span>
            </div>
            <pre className="text-sm text-gray-300 bg-gray-900 p-3 rounded overflow-x-auto">
              {step.commands?.join('\n') || 'No commands'}
            </pre>
          </div>
          
          {step.logs && (
            <div className="p-4 border-t border-gray-700">
              <div className="flex items-center space-x-2 text-sm text-gray-400 mb-2">
                <Terminal className="h-4 w-4" />
                <span>Logs</span>
              </div>
              <div className="log-container">
                <pre>{step.logs}</pre>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function PipelineRun({ run, logs }) {
  const [expandedSteps, setExpandedSteps] = useState(new Set([0]))

  const toggleStep = (index) => {
    setExpandedSteps((prev) => {
      const next = new Set(prev)
      if (next.has(index)) {
        next.delete(index)
      } else {
        next.add(index)
      }
      return next
    })
  }

  const sortedSteps = [...(run.steps || [])].sort((a, b) => a.step_order - b.step_order)

  // Merge logs into steps
  const stepsWithLogs = sortedSteps.map((step) => {
    const logData = logs?.steps?.find((l) => l.name === step.name)
    return {
      ...step,
      logs: logData?.logs || step.logs,
      commands: step.commands,
    }
  })

  return (
    <div>
      <div className="bg-gray-800 rounded-lg p-6 mb-6 border border-gray-700">
        <div className="flex items-center justify-between mb-4">
          <StatusBadge status={run.status} size="lg" />
          {run.started_at && (
            <span className="text-sm text-gray-400">
              Started {formatDistanceToNow(new Date(run.started_at), { addSuffix: true })}
            </span>
          )}
        </div>
        
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <span className="text-gray-500">Branch</span>
            <p className="font-medium">{run.branch}</p>
          </div>
          <div>
            <span className="text-gray-500">Commit</span>
            <p className="font-mono">{run.commit_sha?.slice(0, 7)}</p>
          </div>
          <div>
            <span className="text-gray-500">Triggered by</span>
            <p>{run.triggered_by || 'Unknown'}</p>
          </div>
          <div>
            <span className="text-gray-500">Duration</span>
            <p>
              {run.started_at && run.finished_at
                ? `${Math.round((new Date(run.finished_at) - new Date(run.started_at)) / 1000)}s`
                : run.started_at
                ? 'Running...'
                : 'Pending'}
            </p>
          </div>
        </div>
      </div>

      <h3 className="text-lg font-semibold mb-4">Steps ({stepsWithLogs.length})</h3>
      <div className="space-y-3">
        {stepsWithLogs.map((step, index) => (
          <StepCard
            key={step.id || index}
            step={step}
            isExpanded={expandedSteps.has(index)}
            onToggle={() => toggleStep(index)}
          />
        ))}
      </div>
    </div>
  )
}

export default PipelineRun
