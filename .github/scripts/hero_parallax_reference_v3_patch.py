from pathlib import Path
import re

p = Path('landing.html')
s = p.read_text(encoding='utf-8')

# Remove the previous advanced runtime so it cannot keep moving the command mockup.
s = re.sub(
    r'<script>\s*/\* advanced parallax only for the hero: layered system network \+ mouse \+ scroll \+ ambient drift \*/.*?</script>\s*',
    '',
    s,
    flags=re.S,
)

# Idempotency for this patch.
s = re.sub(r'\n?/\* HERO PARALLAX V3 - MATCH REFERENCE \*/.*?/\* END HERO PARALLAX V3 \*/\n?', '\n', s, flags=re.S)
s = re.sub(r'<script>\s*/\* HERO PARALLAX V3 RUNTIME \*/.*?</script>\s*', '', s, flags=re.S)

css = r"""
/* HERO PARALLAX V3 - MATCH REFERENCE */
.hero{isolation:isolate;perspective:1800px;overflow:hidden}
.hero>.hero-bg{z-index:0!important}
.hero>.wrap{position:relative;z-index:6}
.hero-system-parallax,.hero-advanced-parallax{display:none!important}

/* real product mockup must always sit above the background composition */
.hero .command{position:relative;z-index:10;isolation:isolate;transform-style:preserve-3d;will-change:transform}
.hero .os-window{z-index:3}
.hero .float{z-index:20!important;transform:translateZ(90px)}
.hero .float.a,.hero .float.b{z-index:24!important}

.hero-parallax-v3{position:absolute;inset:-10% -6% -14%;z-index:2;pointer-events:none;overflow:hidden;transform-style:preserve-3d;perspective:1800px;-webkit-mask-image:linear-gradient(180deg,transparent 0,#000 7%,#000 93%,transparent 100%);mask-image:linear-gradient(180deg,transparent 0,#000 7%,#000 93%,transparent 100%)}
.hp3-layer{position:absolute;inset:-7%;transform-style:preserve-3d;will-change:transform}
.hp3-ambient{background:radial-gradient(circle at 76% 24%,rgba(255,91,0,.17),transparent 19%),radial-gradient(circle at 61% 73%,rgba(255,91,0,.085),transparent 25%),radial-gradient(circle at 91% 62%,rgba(76,98,124,.10),transparent 26%);opacity:.92}

/* perspective technical floor, like the visual reference */
.hp3-grid{position:absolute;inset:-8% -10% -4% 17%;opacity:.44;background-image:linear-gradient(rgba(255,255,255,.04) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.04) 1px,transparent 1px);background-size:70px 70px;transform:perspective(950px) rotateX(61deg) rotateZ(-3deg) translateY(31%);transform-origin:50% 74%;-webkit-mask-image:linear-gradient(90deg,transparent 0,rgba(0,0,0,.35) 20%,#000 48%,rgba(0,0,0,.92) 100%);mask-image:linear-gradient(90deg,transparent 0,rgba(0,0,0,.35) 20%,#000 48%,rgba(0,0,0,.92) 100%)}
.hp3-grid:after{content:"";position:absolute;inset:0;background:linear-gradient(90deg,transparent 13%,rgba(255,91,0,.035) 38%,rgba(255,91,0,.18) 54%,transparent 73%);animation:hp3GridSweep 7.2s ease-in-out infinite alternate}
@keyframes hp3GridSweep{from{transform:translateX(-24%)}to{transform:translateX(27%)}}

/* connected system graph behind the product window */
.hp3-network{position:absolute;inset:2% -3% 0 26%;opacity:.92;filter:drop-shadow(0 0 12px rgba(255,91,0,.07))}
.hp3-network svg{width:100%;height:100%;overflow:visible}
.hp3-wire{fill:none;stroke:rgba(255,255,255,.10);stroke-width:1.1;vector-effect:non-scaling-stroke}
.hp3-wire.hot{stroke:rgba(255,91,0,.38);stroke-dasharray:8 18;animation:hp3Wire 8.5s linear infinite;filter:drop-shadow(0 0 7px rgba(255,91,0,.22))}
.hp3-wire.hot.rev{animation-duration:12s;animation-direction:reverse}
@keyframes hp3Wire{to{stroke-dashoffset:-108}}
.hp3-node{fill:#ff5b00;filter:drop-shadow(0 0 10px #ff5b00);animation:hp3Node 2.7s ease-in-out infinite}
.hp3-node.n2{animation-delay:-.8s}.hp3-node.n3{animation-delay:-1.6s}.hp3-node.n4{animation-delay:-2.2s}
@keyframes hp3Node{0%,100%{opacity:.24;r:2.3px}50%{opacity:1;r:4.4px}}

/* large floating interface cards around the hero, not tiny decorative labels */
.hp3-panel{position:absolute;width:242px;min-height:112px;padding:18px 18px 16px;border:1px solid rgba(255,255,255,.115);border-radius:21px;background:linear-gradient(145deg,rgba(23,29,36,.80),rgba(8,11,15,.43));box-shadow:0 32px 82px rgba(0,0,0,.38),inset 0 1px rgba(255,255,255,.038),0 0 44px rgba(255,91,0,.022);backdrop-filter:blur(13px);color:#e8edf2;opacity:.48}
.hp3-icon{width:36px;height:36px;border-radius:11px;display:inline-grid;place-items:center;margin-right:12px;border:1px solid rgba(255,255,255,.08);background:rgba(255,255,255,.025);color:#a3abb4;font-size:17px;vertical-align:middle}
.hp3-panel b{font:700 13px Manrope,sans-serif;vertical-align:middle;color:#e1e6eb}
.hp3-panel i{display:block;height:8px;border-radius:8px;background:#2a3139;margin-top:14px;width:72%}
.hp3-panel i:last-child{width:48%;margin-top:8px;opacity:.78}
.hp3-panel:after{content:"";position:absolute;left:18px;right:18px;bottom:10px;height:1px;background:linear-gradient(90deg,rgba(255,91,0,.72),transparent 68%);transform:scaleX(.30);transform-origin:left;opacity:.48;animation:hp3PanelLine 4s ease-in-out infinite alternate}
@keyframes hp3PanelLine{to{transform:scaleX(1);opacity:.85}}
.hp3-p1{left:-3%;top:7%;transform:rotate(-7deg)}
.hp3-p2{left:44%;top:0;transform:rotate(3deg)}
.hp3-p3{right:-3%;top:8%;transform:rotate(6deg)}
.hp3-p4{left:42%;bottom:0;transform:rotate(-4deg)}
.hp3-p5{right:-2%;bottom:-1%;transform:rotate(5deg)}
.hp3-p6{left:7%;bottom:10%;transform:rotate(5deg);opacity:.27}
.hp3-p2,.hp3-p4{opacity:.41}

/* larger ghost dashboard panes to make the scene feel spatial, not empty */
.hp3-ghost{position:absolute;border:1px solid rgba(255,255,255,.07);border-radius:26px;background:linear-gradient(145deg,rgba(17,22,28,.32),rgba(7,10,13,.12));box-shadow:0 36px 95px rgba(0,0,0,.20);backdrop-filter:blur(5px);opacity:.30}
.hp3-g1{width:420px;height:245px;left:23%;top:22%;transform:rotate(-5deg)}
.hp3-g2{width:500px;height:280px;right:-5%;top:31%;transform:rotate(4deg)}
.hp3-ghost:before{content:"";position:absolute;left:28px;right:28px;top:31px;height:10px;border-radius:10px;background:linear-gradient(90deg,rgba(255,91,0,.58) 0 18%,#323a43 18% 42%,transparent 42%)}
.hp3-ghost:after{content:"";position:absolute;left:28px;right:28px;top:68px;bottom:28px;border-top:1px solid rgba(255,255,255,.055);background:repeating-linear-gradient(180deg,transparent 0 35px,rgba(255,255,255,.025) 36px,transparent 37px)}

/* orange light architecture and depth accents from the generated reference */
.hp3-rings{position:absolute;width:min(880px,65vw);aspect-ratio:1;right:-14vw;top:-2%;border-radius:50%;opacity:.50;background:repeating-radial-gradient(circle,transparent 0 58px,rgba(255,255,255,.048) 59px,transparent 60px 94px),conic-gradient(from 145deg,transparent 0 13%,rgba(255,91,0,.24) 17%,transparent 23% 51%,rgba(255,91,0,.11) 58%,transparent 64% 100%);-webkit-mask-image:radial-gradient(circle,#000 0 50%,rgba(0,0,0,.55) 68%,transparent 80%);mask-image:radial-gradient(circle,#000 0 50%,rgba(0,0,0,.55) 68%,transparent 80%);animation:hp3Ring 39s linear infinite}
@keyframes hp3Ring{to{rotate:360deg}}
.hp3-beam-v{position:absolute;top:-12%;bottom:-12%;width:2px;right:20%;opacity:.61;background:linear-gradient(180deg,transparent,rgba(255,91,0,.16) 19%,rgba(255,91,0,.96) 49%,rgba(255,91,0,.14) 79%,transparent);box-shadow:0 0 21px rgba(255,91,0,.34);animation:hp3BeamV 5.7s ease-in-out infinite alternate}
@keyframes hp3BeamV{from{transform:translateX(-100px);opacity:.25}to{transform:translateX(115px);opacity:.65}}
.hp3-beam-h{position:absolute;left:29%;right:-5%;height:1px;top:35%;opacity:.59;background:linear-gradient(90deg,transparent,rgba(255,91,0,.16),rgba(255,91,0,.86),rgba(255,91,0,.1),transparent);box-shadow:0 0 16px rgba(255,91,0,.25);animation:hp3BeamH 7.1s ease-in-out infinite}
@keyframes hp3BeamH{0%,100%{transform:translateY(-16vh);opacity:.18}50%{transform:translateY(43vh);opacity:.61}}
.hp3-dot{position:absolute;width:5px;height:5px;border-radius:50%;background:#ff6410;box-shadow:0 0 15px rgba(255,91,0,.95);opacity:.68;animation:hp3Dot 3.5s ease-in-out infinite}
.hp3-dot:nth-child(2n){animation-duration:5s}.hp3-dot:nth-child(3n){animation-delay:-1.8s}
@keyframes hp3Dot{0%,100%{transform:scale(.55);opacity:.2}50%{transform:scale(1.55);opacity:.92}}

/* cinematic mask: keeps text clean while the right side remains rich */
.hp3-vignette{position:absolute;inset:0;z-index:8;background:radial-gradient(ellipse at 69% 46%,transparent 0 19%,rgba(8,10,13,.10) 46%,rgba(8,10,13,.55) 100%),linear-gradient(90deg,rgba(8,10,13,.96) 0%,rgba(8,10,13,.83) 28%,rgba(8,10,13,.29) 58%,rgba(8,10,13,.28) 80%,rgba(8,10,13,.61) 100%)}

@media(max-width:900px){
  .hero-parallax-v3{inset:-3% -30% -8%}
  .hp3-network{left:12%;opacity:.52}
  .hp3-grid{left:0;right:-48%;opacity:.27}
  .hp3-rings{width:114vw;right:-68vw;opacity:.29}
  .hp3-panel{width:166px;min-height:78px;padding:13px;opacity:.17}
  .hp3-icon{width:27px;height:27px;font-size:13px}
  .hp3-panel i{height:6px;margin-top:9px}
  .hp3-p1,.hp3-p2,.hp3-p6,.hp3-g1{display:none}
  .hp3-p3{right:2%;top:10%}.hp3-p4{left:auto;right:41%;bottom:4%}.hp3-p5{right:1%;bottom:1%}
  .hp3-g2{right:-28%;width:360px;height:220px;opacity:.18}
  .hp3-vignette{background:linear-gradient(180deg,rgba(8,10,13,.47),rgba(8,10,13,.69))}
  .hero .float.a{right:0!important;top:3%!important;z-index:24!important}
}
@media(prefers-reduced-motion:reduce){.hp3-grid:after,.hp3-wire.hot,.hp3-node,.hp3-panel:after,.hp3-rings,.hp3-beam-v,.hp3-beam-h,.hp3-dot{animation:none!important}}
/* END HERO PARALLAX V3 */
"""

runtime = r"""
<script>
/* HERO PARALLAX V3 RUNTIME */
(()=>{
  const hero=document.querySelector('.hero');
  if(!hero || hero.querySelector('.hero-parallax-v3')) return;
  hero.querySelectorAll('.hero-system-parallax,.hero-advanced-parallax').forEach(el=>el.remove());

  const root=document.createElement('div');
  root.className='hero-parallax-v3';
  root.setAttribute('aria-hidden','true');
  root.innerHTML=`
    <div class="hp3-layer hp3-ambient" data-depth="0.07"></div>
    <div class="hp3-layer" data-depth="0.13"><div class="hp3-grid"></div></div>
    <div class="hp3-layer" data-depth="0.18"><div class="hp3-ghost hp3-g1"></div><div class="hp3-ghost hp3-g2"></div></div>
    <div class="hp3-layer" data-depth="0.23">
      <div class="hp3-rings"></div>
      <div class="hp3-network"><svg viewBox="0 0 1200 760" preserveAspectRatio="none">
        <path class="hp3-wire" d="M15 142 C180 60 310 225 470 158 S810 78 1170 180"/><path class="hp3-wire hot" d="M15 142 C180 60 310 225 470 158 S810 78 1170 180"/>
        <path class="hp3-wire" d="M70 545 C275 390 385 600 610 456 S910 388 1180 548"/><path class="hp3-wire hot rev" d="M70 545 C275 390 385 600 610 456 S910 388 1180 548"/>
        <path class="hp3-wire" d="M248 52 C330 222 272 344 492 418 S820 438 970 725"/><path class="hp3-wire hot" d="M248 52 C330 222 272 344 492 418 S820 438 970 725"/>
        <path class="hp3-wire" d="M1020 28 C812 180 882 302 674 358 S338 342 122 718"/><path class="hp3-wire hot rev" d="M1020 28 C812 180 882 302 674 358 S338 342 122 718"/>
        <circle class="hp3-node" cx="470" cy="158" r="3"/><circle class="hp3-node n2" cx="610" cy="456" r="3"/><circle class="hp3-node n3" cx="492" cy="418" r="3"/><circle class="hp3-node n4" cx="882" cy="302" r="3"/>
      </svg></div>
    </div>
    <div class="hp3-layer" data-depth="0.34">
      <div class="hp3-panel hp3-p1"><span class="hp3-icon">◎</span><b>Cliente</b><i></i><i></i></div>
      <div class="hp3-panel hp3-p2"><span class="hp3-icon">⌁</span><b>Orçamento</b><i></i><i></i></div>
      <div class="hp3-panel hp3-p3"><span class="hp3-icon">◷</span><b>Prazo</b><i></i><i></i></div>
      <div class="hp3-panel hp3-p4"><span class="hp3-icon">⚙</span><b>Peças</b><i></i><i></i></div>
      <div class="hp3-panel hp3-p5"><span class="hp3-icon">◇</span><b>Entrega</b><i></i><i></i></div>
      <div class="hp3-panel hp3-p6"><span class="hp3-icon">↺</span><b>Garantia</b><i></i><i></i></div>
    </div>
    <div class="hp3-layer" data-depth="0.48">
      <div class="hp3-beam-v"></div><div class="hp3-beam-h"></div>
      <i class="hp3-dot" style="left:34%;top:15%"></i><i class="hp3-dot" style="left:46%;top:36%"></i><i class="hp3-dot" style="left:58%;top:13%"></i><i class="hp3-dot" style="left:70%;top:47%"></i><i class="hp3-dot" style="left:82%;top:25%"></i><i class="hp3-dot" style="left:91%;top:63%"></i><i class="hp3-dot" style="left:56%;top:76%"></i><i class="hp3-dot" style="left:74%;top:85%"></i>
    </div>
    <div class="hp3-vignette"></div>`;

  const bg=hero.querySelector('.hero-bg');
  if(bg) bg.insertAdjacentElement('afterend',root); else hero.prepend(root);

  const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  if(reduced) return;

  const layers=[...root.querySelectorAll('.hp3-layer')];
  const command=hero.querySelector('.command');
  let tx=0,ty=0,mx=0,my=0,scroll=0,targetScroll=0,last=performance.now();

  const readScroll=()=>{
    const r=hero.getBoundingClientRect();
    const vh=innerHeight||1;
    targetScroll=Math.max(-1.1,Math.min(1.1,(vh*.48-r.top)/vh));
  };
  readScroll();

  hero.addEventListener('pointermove',e=>{
    const r=hero.getBoundingClientRect();
    tx=((e.clientX-r.left)/r.width-.5)*2;
    ty=((e.clientY-r.top)/r.height-.5)*2;
  },{passive:true});
  hero.addEventListener('pointerleave',()=>{tx=0;ty=0},{passive:true});
  addEventListener('scroll',readScroll,{passive:true});
  addEventListener('resize',readScroll,{passive:true});

  const frame=now=>{
    const dt=Math.min(42,now-last);last=now;
    const ease=1-Math.pow(.002,dt/1000);
    mx+=(tx-mx)*ease;my+=(ty-my)*ease;scroll+=(targetScroll-scroll)*ease;
    layers.forEach((layer,i)=>{
      const d=Number(layer.dataset.depth||.2);
      const driftX=Math.sin(now*.00022+i*1.7)*5*d;
      const driftY=Math.cos(now*.00018+i*1.31)*4*d;
      const x=mx*62*d+driftX;
      const y=my*36*d-scroll*122*d+driftY;
      const z=d*125;
      const rz=mx*(i-1.5)*.22;
      layer.style.transform=`translate3d(${x}px,${y}px,${z}px) rotateZ(${rz}deg)`;
    });
    if(command) command.style.transform=`translate3d(${mx*7}px,${my*4-scroll*9}px,0)`;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
})();
</script>
"""

s = s.replace('</style>', css + '\n</style>', 1)
s = s.replace('</body>', runtime + '\n</body>', 1)
p.write_text(s, encoding='utf-8')

# Fail loudly if the intended fix is not present.
out = p.read_text(encoding='utf-8')
assert 'HERO PARALLAX V3 - MATCH REFERENCE' in out
assert 'hero-parallax-v3' in out
assert '.hero .float.a,.hero .float.b{z-index:24!important}' in out
assert 'advanced parallax only for the hero: layered system network + mouse + scroll + ambient drift' not in out
print('hero parallax reference v3 patch applied')
