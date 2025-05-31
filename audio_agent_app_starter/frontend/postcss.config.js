// frontend/postcss.config.js
module.exports = {
  plugins: {
    'tailwindcss/nesting': {}, // Optional: if you use Tailwind's nesting features or a custom nesting plugin
    tailwindcss: {},          // Tailwind CSS plugin
    autoprefixer: {},       // Autoprefixer for vendor prefixes
    // You can add other PostCSS plugins here if needed, e.g., cssnano for minification in production
    // ...(process.env.NODE_ENV === 'production' ? { cssnano: {} } : {})
  },
};
