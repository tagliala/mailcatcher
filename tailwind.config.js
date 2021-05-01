module.exports = {
  purge: [
    './assets/javascripts/**/*.coffee',
    './views/**/*.erb'
  ],
  darkMode: 'media', // or 'media' or 'class'
  theme: {
    extend: {
      cursor: {
        'ns-resize': 'ns-resize'
      }
    },
  },
  variants: {
    extend: {},
  },
  plugins: [],
}
