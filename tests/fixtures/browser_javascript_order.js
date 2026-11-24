order += 'D';
document.addEventListener('DOMContentLoaded', function () {
    if (order !== 'ABCDE') throw new Error('script order');
    document.getElementById('out').textContent = order;
});
