document.addEventListener('DOMContentLoaded',()=>{
  const input=document.getElementById('input');
  const status=document.getElementById('status');
  let frames=0;
  const spinner=['*','@','#','&','%'];
  function update(){
    status.textContent=`thinking ${spinner[frames%spinner.length]}`;
    frames+=1;
    requestAnimationFrame(update);
  }
  // start spinner when a request would be sent; placeholder starts immediately
  update();
});