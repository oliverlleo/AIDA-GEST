from pathlib import Path
import re

p = Path('landing.html')
s = p.read_text(encoding='utf-8')

# Remove all previous hero-parallax attempts so only the reference-matched scene remains.
s = re.sub(r'<script>\s*/\* HERO PARALLAX V3 RUNTIME \*/.*?</script>\s*', '', s, flags=re.S)
s = re.sub(r'<script>\s*/\* HERO PARALLAX V4 RUNTIME \*/.*?</script>\s*', '', s, flags=re.S)
s = re.sub(r'<script>\s*/\* hero system-only parallax \*/.*?</script>\s*', '', s, flags=re.S)
s = re.sub(r'<script>\s*/\* advanced parallax only for the hero: layered system network \+ mouse \+ scroll \+ ambient drift \*/.*?</script>\s*', '', s, flags=re.S)
s = re.sub(r'\n?/\* HERO PARALLAX V3 - MATCH REFERENCE \*/.*?/\* END HERO PARALLAX V3 \*/\n?', '\n', s, flags=re.S)
s = re.sub(r'\n?/\* HERO PARALLAX V4 - GENERATED REFERENCE MATCH \*/.*?/\* END HERO PARALLAX V4 \*/\n?', '\n', s, flags=re.S)
s = re.sub(r'\n?/\* HERO PARALLAX EXACT GENERATED REFERENCE \*/.*?/\* END HERO PARALLAX EXACT GENERATED REFERENCE \*/\n?', '\n', s, flags=re.S)
s = re.sub(r'<script>\s*/\* HERO PARALLAX EXACT GENERATED REFERENCE RUNTIME \*/.*?</script>\s*', '', s, flags=re.S)

css = r'''
/* HERO PARALLAX EXACT GENERATED REFERENCE */
.hero{isolation:isolate;perspective:1800px;overflow:hidden}
.hero>.hero-bg{z-index:0!important}
.hero>.wrap{position:relative;z-index:8}
.hero-system-parallax,.hero-advanced-parallax,.hero-parallax-v3,.hero-parallax-v4{display:none!important}

/* Preserve the original page composition; the parallax lives behind the real product mockup. */
.hero .command{position:relative;z-index:12;isolation:isolate;transform-style:preserve-3d;will-change:transform}
.hero .os-window{z-index:4}
.hero .float{z-index:60!important;will-change:transform;transform-style:preserve-3d}
.hero .float.a{z-index:70!important;right:-2%!important;top:3%!important}
.hero .float.b{z-index:70!important;left:-3%!important;bottom:4%!important}

.hero-parallax-exact{position:absolute;inset:-4% -3% -8%;z-index:2;pointer-events:none;overflow:hidden;transform-style:preserve-3d;perspective:1800px}
.hpe-layer{position:absolute;inset:-4%;transform-style:preserve-3d;will-change:transform}

/* Same dark glass atmosphere as the generated reference: no grid, no rings, no busy network. */
.hpe-ambient{background:radial-gradient(circle at 72% 14%,rgba(255,91,0,.105),transparent 16%),radial-gradient(circle at 92% 48%,rgba(255,91,0,.085),transparent 18%),radial-gradient(circle at 68% 86%,rgba(255,91,0,.07),transparent 19%);opacity:.92}

/* Five large background UI cards matching the reference positions. */
.hpe-card{position:absolute;width:292px;height:138px;border:1px solid rgba(255,255,255,.075);border-radius:20px;background:linear-gradient(145deg,rgba(18,23,29,.34),rgba(7,9,12,.12));box-shadow:0 30px 90px rgba(0,0,0,.30),inset 0 1px rgba(255,255,255,.018),0 0 34px rgba(255,91,0,.018);backdrop-filter:blur(6px);opacity:.28;overflow:hidden}
.hpe-card .ico{position:absolute;left:24px;top:25px;width:42px;height:42px;border-radius:11px;border:1px solid rgba(255,255,255,.07);display:grid;place-items:center;color:rgba(198,205,214,.32);font-size:22px}
.hpe-card .name{position:absolute;left:82px;top:29px;color:rgba(211,217,224,.34);font:700 14px Manrope,sans-serif}
.hpe-card .bar{position:absolute;left:82px;height:8px;border-radius:8px;background:rgba(132,143,155,.10)}
.hpe-card .b1{top:58px;width:115px}.hpe-card .b2{top:78px;width:82px}
.hpe-c1{left:2.5%;top:8%;transform:rotate(7deg)}
.hpe-c2{left:48%;top:9%;transform:rotate(2deg)}
.hpe-c3{right:-4%;top:5%;transform:rotate(6deg)}
.hpe-c4{left:44%;bottom:1%;transform:rotate(-3deg)}
.hpe-c5{right:-4%;bottom:0;transform:rotate(5deg)}

/* Large almost-invisible panel behind the left-center, visible in the generated concept. */
.hpe-ghost{position:absolute;left:13%;top:23%;width:470px;height:205px;border-radius:28px;border:1px solid rgba(255,255,255,.035);background:linear-gradient(145deg,rgba(18,22,28,.18),rgba(7,9,12,.07));box-shadow:0 40px 110px rgba(0,0,0,.22);opacity:.18;transform:rotate(-3deg)}
.hpe-ghost:before{content:"";position:absolute;left:32px;top:34px;width:62%;height:10px;border-radius:9px;background:rgba(255,255,255,.035);box-shadow:0 30px 0 rgba(255,255,255,.022),0 60px 0 rgba(255,255,255,.015)}

/* Long orange light rails/dashes from the generated image. */
.hpe-rail{position:absolute;opacity:.50;filter:drop-shadow(0 0 7px rgba(255,91,0,.22))}
.hpe-rail.v1{width:1px;height:74%;left:71%;top:-2%;background:linear-gradient(180deg,transparent,rgba(255,91,0,.16) 10%,rgba(255,91,0,.85) 48%,rgba(255,91,0,.10) 88%,transparent)}
.hpe-rail.v2{width:1px;height:70%;right:5%;top:18%;background:linear-gradient(180deg,transparent,rgba(255,91,0,.10),rgba(255,91,0,.76),rgba(255,91,0,.08),transparent)}
.hpe-rail.h1{height:1px;width:52%;left:53%;top:14%;background:linear-gradient(90deg,transparent,rgba(255,91,0,.13),rgba(255,91,0,.45),transparent);transform:rotate(8deg)}
.hpe-rail.h2{height:1px;width:55%;left:48%;bottom:12%;background:linear-gradient(90deg,transparent,rgba(255,91,0,.12),rgba(255,91,0,.48),transparent);transform:rotate(5deg)}
.hpe-rail.h3{height:1px;width:40%;left:51%;top:53%;background:linear-gradient(90deg,transparent,rgba(255,91,0,.10),rgba(255,91,0,.34),transparent);transform:rotate(-4deg)}
.hpe-dashes{position:absolute;left:62%;top:11%;width:230px;height:2px;opacity:.52;background:repeating-linear-gradient(90deg,rgba(255,91,0,.62) 0 5px,transparent 5px 12px);transform:rotate(8deg);filter:drop-shadow(0 0 5px rgba(255,91,0,.22))}

/* Sparse warm lights only. */
.hpe-dot{position:absolute;width:6px;height:6px;border-radius:50%;background:#ff6210;box-shadow:0 0 15px rgba(255,91,0,.86);opacity:.56;animation:hpeBlink 3.8s ease-in-out infinite}
.hpe-dot.d2{animation-delay:-1.3s}.hpe-dot.d3{animation-delay:-2.5s}
@keyframes hpeBlink{0%,100%{opacity:.22;transform:scale(.7)}50%{opacity:.88;transform:scale(1.25)}}
.hpe-glow{position:absolute;right:-7%;top:22%;width:450px;height:560px;background:radial-gradient(ellipse,rgba(255,91,0,.105),rgba(255,91,0,.025) 46%,transparent 72%);filter:blur(18px);opacity:.78}

/* Keep headline area readable, exactly like the reference. */
.hpe-vignette{position:absolute;inset:0;z-index:8;background:linear-gradient(90deg,rgba(8,10,13,.90) 0%,rgba(8,10,13,.82) 27%,rgba(8,10,13,.31) 49%,rgba(8,10,13,.06) 69%,rgba(8,10,13,.18) 100%)}

@media(max-width:900px){.hero-parallax-exact{inset:-2% -24% -5%}.hpe-c1,.hpe-c2,.hpe-ghost{display:none}.hpe-c3{right:0;top:4%}.hpe-c4{left:auto;right:37%;bottom:0}.hpe-c5{right:0;bottom:-2%}.hpe-vignette{background:linear-gradient(180deg,rgba(8,10,13,.40),rgba(8,10,13,.62))}.hero .float.a{right:1%!important;top:2%!important}.hero .float.b{left:0!important;bottom:2%!important}}
@media(prefers-reduced-motion:reduce){.hpe-dot{animation:none!important}}
/* END HERO PARALLAX EXACT GENERATED REFERENCE */
'''

runtime = r'''
<script>
/* HERO PARALLAX EXACT GENERATED REFERENCE RUNTIME */
(()=>{
  const hero=document.querySelector('.hero');
  if(!hero || hero.querySelector('.hero-parallax-exact')) return;
  hero.querySelectorAll('.hero-system-parallax,.hero-advanced-parallax,.hero-parallax-v3,.hero-parallax-v4').forEach(el=>el.remove());

  const scene=document.createElement('div');
  scene.className='hero-parallax-exact';
  scene.setAttribute('aria-hidden','true');
  scene.innerHTML=`
    <div class="hpe-layer hpe-ambient" data-depth="0.05"></div>
    <div class="hpe-layer" data-depth="0.075">
      <div class="hpe-ghost"></div>
      <div class="hpe-card hpe-c1"><span class="ico">♙</span><b class="name">Cliente</b><i class="bar b1"></i><i class="bar b2"></i></div>
      <div class="hpe-card hpe-c2"><span class="ico">⌕</span><b class="name">Orçamento</b><i class="bar b1"></i><i class="bar b2"></i></div>
      <div class="hpe-card hpe-c3"><span class="ico">◷</span><b class="name">Prazo</b><i class="bar b1"></i><i class="bar b2"></i></div>
      <div class="hpe-card hpe-c4"><span class="ico">⚙</span><b class="name">Peças</b><i class="bar b1"></i><i class="bar b2"></i></div>
      <div class="hpe-card hpe-c5"><span class="ico">◇</span><b class="name">Entrega</b><i class="bar b1"></i><i class="bar b2"></i></div>
    </div>
    <div class="hpe-layer" data-depth="0.12">
      <i class="hpe-rail v1"></i><i class="hpe-rail v2"></i><i class="hpe-rail h1"></i><i class="hpe-rail h2"></i><i class="hpe-rail h3"></i><i class="hpe-dashes"></i><i class="hpe-glow"></i>
    </div>
    <div class="hpe-layer" data-depth="0.18">
      <i class="hpe-dot" style="left:63%;top:11%"></i><i class="hpe-dot d2" style="left:71%;top:32%"></i><i class="hpe-dot d3" style="left:92%;top:29%"></i><i class="hpe-dot d2" style="left:76%;top:80%"></i><i class="hpe-dot" style="left:96%;top:57%"></i>
    </div>
    <div class="hpe-vignette"></div>`;

  const bg=hero.querySelector('.hero-bg');
  if(bg) bg.insertAdjacentElement('afterend',scene); else hero.prepend(scene);

  if(matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const layers=[...scene.querySelectorAll('.hpe-layer')];
  const command=hero.querySelector('.command');
  const floatA=hero.querySelector('.float.a');
  const floatB=hero.querySelector('.float.b');
  let tx=0,ty=0,mx=0,my=0,sp=0,tsp=0,last=performance.now();

  const readScroll=()=>{
    const r=hero.getBoundingClientRect();
    const vh=innerHeight||1;
    tsp=Math.max(-1,Math.min(1,(vh*.48-r.top)/vh));
  };
  readScroll();

  hero.addEventListener('pointermove',e=>{
    if(innerWidth<800)return;
    const r=hero.getBoundingClientRect();
    tx=((e.clientX-r.left)/r.width-.5)*2;
    ty=((e.clientY-r.top)/r.height-.5)*2;
  },{passive:true});
  hero.addEventListener('pointerleave',()=>{tx=0;ty=0},{passive:true});
  addEventListener('scroll',readScroll,{passive:true});
  addEventListener('resize',readScroll,{passive:true});

  const frame=now=>{
    const dt=Math.min(40,now-last);last=now;
    const ease=1-Math.pow(.0018,dt/1000);
    mx+=(tx-mx)*ease;my+=(ty-my)*ease;sp+=(tsp-sp)*ease;
    layers.forEach((layer,i)=>{
      const d=Number(layer.dataset.depth||.08);
      const driftX=Math.sin(now*.00018+i*1.7)*2.5;
      const driftY=Math.cos(now*.00015+i*1.1)*2;
      const x=mx*82*d+driftX*d;
      const y=my*50*d-sp*118*d+driftY*d;
      layer.style.transform=`translate3d(${x}px,${y}px,${d*150}px)`;
    });
    if(command) command.style.transform=`translate3d(${mx*5}px,${my*3-sp*7}px,0)`;
    if(floatA) floatA.style.transform=`translate3d(${mx*10}px,${my*7-sp*12}px,120px)`;
    if(floatB) floatB.style.transform=`translate3d(${mx*-8}px,${my*-5-sp*14}px,130px)`;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
})();
</script>
'''

s = s.replace('</style>', css + '\n</style>', 1)
s = s.replace('</body>', runtime + '\n</body>', 1)
p.write_text(s, encoding='utf-8')
