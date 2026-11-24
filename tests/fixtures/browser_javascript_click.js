var count = 0;
var out = document.getElementById('out');
var run = document.getElementById('run');
out.textContent = 'Ready🙂';
run.addEventListener('click', function(e){e.preventDefault(); throw new Error('listener error');});
function removed() { count += 100; }
function increment() { count++; out.textContent = 'Нажатий: ' + count + '🙂'; }
run.addEventListener('click', removed);
run.addEventListener('click', increment);
run.removeEventListener('click', removed);
run.addEventListener('click', increment);
document.getElementById('hang').onclick = function() { out.textContent = 'Partial'; while (true) {} };
