/***** Tailwind config *****/
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#0b1221',
        panel: '#0f172a',
        accent: '#5ee8ff',
        accent2: '#7af5c9',
        muted: '#9fb3c8'
      },
      fontFamily: {
        display: ['"IBM Plex Sans"', 'system-ui', 'sans-serif'],
        body: ['"IBM Plex Sans"', 'system-ui', 'sans-serif']
      }
    }
  },
  plugins: []
};
