// Recovered CodePen export. Reference only — needs jQuery, imagesLoaded,
// Parallax, Packery and anime.js, none of which this tree carries.
$("#scene").imagesLoaded(function () {
  // Apply random Parallax depths to items
  $("#scene div").each(function () {
    $(this).attr("data-depth", Math.floor(Math.random() * 30) / 200);
  });

  const scene = document.getElementById("scene");
  const parallaxInstance = new Parallax(scene, {
    relativeInput: true,
    scalarY: 100,
    scalarX: 100
  });

  $("#scene").packery({ itemSelector: "div", gutter: 10 });

  anime({
    targets: "#scene div",
    translateX: function () { return anime.random(-100, 100); },
    translateY: function () { return anime.random(-100, 100); },
    easing: "easeInOutBack",
    delay: anime.stagger(50),
    duration: 6000
  });
});
