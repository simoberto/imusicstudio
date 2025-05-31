/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}", // Watches all JS, JSX, TS, TSX files in src
    "./public/index.html",      // Watches index.html for class names
  ],
  darkMode: 'class', // Or 'media' if you prefer OS-level dark mode detection
  theme: {
    extend: {
      fontFamily: {
        // Sets 'Inter' as the default sans-serif font. Fallbacks are standard.
        'sans': ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto', '"Helvetica Neue"', 'Arial', '"Noto Sans"', 'sans-serif', '"Apple Color Emoji"', '"Segoe UI Emoji"', '"Segoe UI Symbol"', '"Noto Color Emoji"'],
      },
      colors: {
        // Custom color palette (examples from the document)
        primary: { // Blue-ish palette
          50: '#f0f9ff', 100: '#e0f2fe', 200: '#bae6fd', 300: '#7dd3fc',
          400: '#38bdf8', 500: '#0ea5e9', 600: '#0284c7', 700: '#0369a1',
          800: '#075985', 900: '#0c4a6e', 950: '#082f49',
        },
        secondary: { // Purple-ish palette
          50: '#faf5ff', 100: '#f3e8ff', 200: '#e9d5ff', 300: '#d8b4fe',
          400: '#c084fc', 500: '#a855f7', 600: '#9333ea', 700: '#7c3aed',
          800: '#6b21a8', 900: '#581c87', 950: '#3b0764',
        },
        accent: { // Orange/Amber palette
          50: '#fff7ed', 100: '#ffedd5', 200: '#fed7aa', 300: '#fdba74',
          400: '#fb923c', 500: '#f97316', 600: '#ea580c', 700: '#c2410c',
          800: '#9a3412', 900: '#7c2d12', 950: '#431407',
        },
        // Specific semantic colors often used
        success: { // Green palette
          50: '#f0fdf4', 100: '#dcfce7', 200: '#bbf7d0', 300: '#86efac',
          400: '#4ade80', 500: '#22c55e', 600: '#16a34a', 700: '#15803d',
          800: '#166534', 900: '#14532d', 950: '#052e16',
        },
        warning: { // Yellow/Amber palette
          50: '#fffbeb', 100: '#fef3c7', 200: '#fde68a', 300: '#fcd34d',
          400: '#fbbf24', 500: '#f59e0b', 600: '#d97706', 700: '#b45309',
          800: '#92400e', 900: '#78350f', 950: '#451a03',
        },
        error: { // Red palette
          50: '#fef2f2', 100: '#fee2e2', 200: '#fecaca', 300: '#fca5a5',
          400: '#f87171', 500: '#ef4444', 600: '#dc2626', 700: '#b91c1c',
          800: '#991b1b', 900: '#7f1d1d', 950: '#450a0a',
        },
        // Dark mode specific theme colors (if needed beyond Tailwind's dark variants)
        // Example: dark: { background: '#0A0A0A', text: '#E0E0E0' }
      },
      backgroundImage: {
        // Custom gradients
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
        'gradient-conic': 'conic-gradient(from 180deg at 50% 50%, var(--tw-gradient-stops))',
        'gradient-primary': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)', // Example primary
        'gradient-secondary': 'linear-gradient(135deg, #a855f7 0%, #667eea 100%)', // Example secondary
        'gradient-dark-main': 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)', // Main app background
        'gradient-purple-blue': 'linear-gradient(135deg, #a855f7 0%, #3b82f6 100%)',
        'gradient-blue-accent': 'linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%)',
        'gradient-green-accent': 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
      },
      animation: {
        // Custom animations based on keyframes
        'spin-slow': 'spin 3s linear infinite',
        'pulse-slow': 'pulse 3s ease-in-out infinite', // Tailwind already has 'pulse'
        'bounce-slow': 'bounce 2s infinite',         // Tailwind already has 'bounce'
        'float': 'float 3s ease-in-out infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
        'slide-up': 'slideUp 0.4s ease-out forwards', // Added forwards
        'slide-down': 'slideDown 0.4s ease-out forwards', // Added forwards
        'fade-in': 'fadeIn 0.5s ease-out forwards',
        'scale-in': 'scaleIn 0.3s ease-out forwards',
      },
      keyframes: {
        // Custom keyframes
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        glow: { // Example glow, can be more complex
          '0%, 100%': { opacity: '0.7', boxShadow: '0 0 10px rgba(168, 85, 247, 0.4)' }, // secondary-500
          '50%': { opacity: '1', boxShadow: '0 0 25px rgba(168, 85, 247, 0.7)' },
        },
        slideUp: {
          '0%': { transform: 'translateY(20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        slideDown: { // From top to current position
          '0%': { transform: 'translateY(-20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        scaleIn: {
          '0%': { transform: 'scale(0.9)', opacity: '0' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        // Tailwind's default spin, pulse, bounce are usually sufficient.
        // spin: { to: { transform: 'rotate(360deg)' } },
        // pulse: { '0%, 100%': { opacity: '1' }, '50%': { opacity: '.5' } },
        // bounce: { '0%, 100%': { transform: 'translateY(-25%)', animationTimingFunction: 'cubic-bezier(0.8,0,1,1)'}, '50%': {transform: 'translateY(0)', animationTimingFunction: 'cubic-bezier(0,0,0.2,1)'} }
      },
      spacing: { // Custom spacing if needed
        '18': '4.5rem', '88': '22rem', '100': '25rem', '128': '32rem',
      },
      borderRadius: { // Custom border radius if needed beyond sm, md, lg, xl, 2xl, 3xl, full
        'xl': '1rem', '2xl': '1.5rem', '3xl': '2rem',
      },
      boxShadow: { // Custom box shadows
        'glow-purple': '0 0 20px rgba(168, 85, 247, 0.4)', // secondary-500
        'glow-blue': '0 0 20px rgba(59, 130, 246, 0.4)',   // primary-500 (approx)
        'glow-lg-purple': '0 0 40px rgba(168, 85, 247, 0.5)',
        'inner-glow-purple': 'inset 0 0 15px rgba(168, 85, 247, 0.3)',
        'glass': '0 8px 32px 0 rgba(31, 38, 135, 0.25)', // Adjusted for subtlety
      },
      backdropBlur: { // Custom backdrop blur values
        'xs': '2px', 'sm': '4px', 'md': '8px', // Tailwind has sm, md, lg, xl etc. by default
      },
      screens: { // Custom screen breakpoints
        'xs': '475px', // Extra small
        '3xl': '1600px', // Larger desktop
      },
      zIndex: { // Custom z-index values
        '60': '60', '70': '70', '80': '80', '90': '90', '100': '100',
      },
      aspectRatio: { // Custom aspect ratios
        '4/3': '4 / 3', '3/2': '3 / 2', '2/3': '2 / 3', '9/16': '9 / 16',
      },
      typography: (theme) => ({ // Custom typography styles
        DEFAULT: {
          css: {
            color: theme('colors.gray.200', '#e5e7eb'), // Default text for prose
            a: {
              color: theme('colors.secondary.400', '#c084fc'),
              '&:hover': { color: theme('colors.secondary.500', '#a855f7')},
            },
            h1: { color: theme('colors.gray.100', '#f3f4f6') },
            h2: { color: theme('colors.gray.100', '#f3f4f6') },
            h3: { color: theme('colors.gray.200', '#e5e7eb') },
            h4: { color: theme('colors.gray.300', '#d1d5db') },
            code: {
              color: theme('colors.primary.300', '#7dd3fc'),
              backgroundColor: theme('colors.gray.800', '#1f2937'),
              padding: '0.2em 0.4em',
              borderRadius: '0.25rem',
            },
            'code::before': { content: '""' }, // Remove backticks from inline code
            'code::after': { content: '""' },
            pre: {
              backgroundColor: theme('colors.gray.800', '#1f2937'),
              color: theme('colors.gray.300', '#d1d5db'),
              boxShadow: theme('boxShadow.md'),
            },
            // Add more prose styles as needed
          },
        },
      }),
    },
  },
  plugins: [
    require('@tailwindcss/forms'),       // Official forms plugin
    require('@tailwindcss/typography'),  // Official typography (prose) plugin
    require('@tailwindcss/aspect-ratio'),// Official aspect ratio plugin

    // Custom plugin for glass morphism (example from original)
    function({ addUtilities }) {
      const newUtilities = {
        '.glass': {
          background: 'rgba(255, 255, 255, 0.05)', // Adjusted for dark theme
          backdropFilter: 'blur(10px) saturate(180%)',
          '-webkit-backdrop-filter': 'blur(10px) saturate(180%)',
          border: '1px solid rgba(255, 255, 255, 0.12)',
        },
        '.glass-darker': { // Example of a darker glass
          background: 'rgba(0, 0, 0, 0.2)',
          backdropFilter: 'blur(12px) saturate(150%)',
          '-webkit-backdrop-filter': 'blur(12px) saturate(150%)',
          border: '1px solid rgba(255, 255, 255, 0.08)',
        },
        '.text-shadow-sm': { textShadow: '0 1px 2px rgba(0, 0, 0, 0.5)'},
        '.text-shadow-md': { textShadow: '0 2px 4px rgba(0, 0, 0, 0.5)'},
        '.text-shadow-lg': { textShadow: '0 4px 8px rgba(0, 0, 0, 0.5)'},
      }
      addUtilities(newUtilities, ['responsive', 'hover']) // Add variants if needed
    },
  ],
}
