if (typeof fetch !== 'undefined' || typeof XMLHttpRequest !== 'undefined') throw new Error('network API');
document.getElementById('out').textContent = 'Loopback works';
