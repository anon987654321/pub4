// Recovered CodePen export (was script.babel). Reference only — not loaded.
// Needs anime.js, which this tree does not carry; see README.md.
// https://tobiasahlin.com/moving-letters/#15

anime
  .timeline({ loop: false })
  .add({
    targets: ".ml15 .word",
    scale: [14, 1],
    opacity: [0, 1],
    easing: "easeOutCirc",
    duration: 800,
    delay: (el, i) => 800 * i
  });

var circle = anime({
  targets: ['.lp'],
  rotate: 3000,
  duration: 100000,
  loop: true
});
