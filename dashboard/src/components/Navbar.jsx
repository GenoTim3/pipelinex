import { Link, useLocation } from 'react-router-dom'
import { Activity, Home, Settings } from 'lucide-react'

function Navbar() {
  const location = useLocation()
  
  const isActive = (path) => {
    return location.pathname === path ? 'bg-gray-700' : 'hover:bg-gray-700'
  }

  return (
    <nav className="bg-gray-800 border-b border-gray-700">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          <Link to="/" className="flex items-center space-x-2">
            <Activity className="h-8 w-8 text-blue-500" />
            <span className="text-xl font-bold">PipelineX</span>
          </Link>
          
          <div className="flex items-center space-x-2">
            <Link
              to="/"
              className={`flex items-center space-x-1 px-3 py-2 rounded-md text-sm font-medium ${isActive('/')}`}
            >
              <Home className="h-4 w-4" />
              <span>Dashboard</span>
            </Link>
            <Link
              to="/settings"
              className={`flex items-center space-x-1 px-3 py-2 rounded-md text-sm font-medium ${isActive('/settings')}`}
            >
              <Settings className="h-4 w-4" />
              <span>Settings</span>
            </Link>
          </div>
        </div>
      </div>
    </nav>
  )
}

export default Navbar
