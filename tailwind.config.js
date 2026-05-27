/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        stryv: {
          bg: '#070707',
          panel: '#101010',
          elevated: '#171717',
          line: '#2a2a2a',
          muted: '#9a9a9a',
          text: '#f4f4f4',
          orange: '#e8581a',
          orangeSoft: '#ff9a4a',
          ember: '#b93a12',
          amber: '#ffb267',
        },
      },
      boxShadow: {
        neon: '0 0 24px rgba(232, 88, 26, 0.24), 0 0 48px rgba(255, 178, 103, 0.08)',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
