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
          orange: '#ff6a00',
          orangeSoft: '#ff8a2a',
        },
      },
      boxShadow: {
        neon: '0 0 28px rgba(255, 106, 0, 0.22)',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
