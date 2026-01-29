import { useEffect, useRef } from 'react'

function StepLog({ logs, autoScroll = true }) {
  const containerRef = useRef(null)

  useEffect(() => {
    if (autoScroll && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight
    }
  }, [logs, autoScroll])

  if (!logs) {
    return (
      <div className="log-container text-gray-500">
        No logs available
      </div>
    )
  }

  return (
    <div ref={containerRef} className="log-container">
      <pre>{logs}</pre>
    </div>
  )
}

export default StepLog
