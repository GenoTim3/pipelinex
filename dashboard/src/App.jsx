import { Routes, Route } from 'react-router-dom'
import Home from './pages/Home'
import RunDetails from './pages/RunDetails'
import Settings from './pages/Settings'
import Navbar from './components/Navbar'

function App() {
  return (
    <div className="min-h-screen bg-gray-900">
      <Navbar />
      <main className="container mx-auto px-4 py-8">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/runs/:runId" element={<RunDetails />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </main>
    </div>
  )
}

export default App
