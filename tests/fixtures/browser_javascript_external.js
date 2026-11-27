if (typeof fetch !== 'function' || typeof XMLHttpRequest !== 'function') throw new Error('network API');
document.getElementById('out').textContent = 'Loopback works';
