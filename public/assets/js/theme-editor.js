(() => {
  const editor = document.getElementById('theme-editor');
  if (!editor) return;
  const field = key => editor.querySelector(`[name="theme_${key}"]`);
  const presets = {
    classic: ['#f2f2f2', '#ffffff', '#111111', '#087f8d', 'sans', '960'],
    cee: ['#edf3f8', '#ffffff', '#152536', '#1465a3', 'sans', '1080'],
    waremono: ['#f6f0e8', '#fffdf9', '#322a25', '#825035', 'serif', '960'],
    sati: ['#f0edf7', '#ffffff', '#30283e', '#705293', 'sans', '800']
  };
  const keys = ['background', 'panel', 'text', 'accent', 'font', 'width'];
  function preview() {
    const colors = keys.slice(0, 4).map(k => /^#[a-f0-9]{6}$/i.test(field(k).value) ? field(k).value : '#111111');
    const font = {sans: 'system-ui,sans-serif', serif: 'Georgia,serif', mono: 'monospace'}[field('font').value] || 'sans-serif';
    const width = /^(720|800|960|1080|1200)$/.test(field('width').value) ? field('width').value : '960';
    document.getElementById('theme-preview').srcdoc = `<!doctype html><meta name="viewport" content="width=device-width"><style>body{background:${colors[0]};color:${colors[2]};font-family:${font};line-height:1.7}main{background:${colors[1]};padding:20px;margin:16px auto;max-width:${width}px;box-sizing:border-box}a{color:${colors[3]}}</style><main><h1>Site theme / サイトのテーマ</h1><p>記事の見出しと本文のプレビューです。</p><a href="#">Read more / 続きを読む</a></main>`;
  }
  field('preset').addEventListener('change', () => {
    keys.forEach((k, i) => { field(k).value = presets[field('preset').value][i]; });
    preview();
  });
  editor.addEventListener('input', preview);
  preview();
})();
