import { CheckCircle, XCircle, Clock, Loader, Circle } from 'lucide-react'

const statusConfig = {
  pending: {
    icon: Circle,
    className: 'bg-gray-500/20 text-gray-400 border-gray-500',
    label: 'Pending',
  },
  queued: {
    icon: Clock,
    className: 'bg-yellow-500/20 text-yellow-400 border-yellow-500',
    label: 'Queued',
  },
  running: {
    icon: Loader,
    className: 'bg-blue-500/20 text-blue-400 border-blue-500',
    label: 'Running',
    animate: true,
  },
  succeeded: {
    icon: CheckCircle,
    className: 'bg-green-500/20 text-green-400 border-green-500',
    label: 'Succeeded',
  },
  failed: {
    icon: XCircle,
    className: 'bg-red-500/20 text-red-400 border-red-500',
    label: 'Failed',
  },
}

function StatusBadge({ status, size = 'md' }) {
  const config = statusConfig[status] || statusConfig.pending
  const Icon = config.icon
  
  const sizeClasses = {
    sm: 'text-xs px-2 py-0.5',
    md: 'text-sm px-2.5 py-1',
    lg: 'text-base px-3 py-1.5',
  }

  return (
    <span
      className={`inline-flex items-center space-x-1 rounded-full border ${config.className} ${sizeClasses[size]}`}
    >
      <Icon className={`h-3.5 w-3.5 ${config.animate ? 'animate-spin' : ''}`} />
      <span>{config.label}</span>
    </span>
  )
}

export default StatusBadge
