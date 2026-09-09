from pathlib import Path
import re

p = Path('landing.html')
s = p.read_text(encoding='utf-8')

# Remove prior hero-parallax experiments/runtime blocks so they cannot compete.
patterns = [
    r'\n?/\* HERO PARALLAX EXACT GENERATED REFERENCE \*/.*?/\* END HERO PARALLAX EXACT GENERATED REFERENCE \*/\n?',
    r'<script>\s*/\* HERO PARALLAX EXACT GENERATED REFERENCE RUNTIME \*/.*?</script>\s*',
    r'\n?/\* HERO PARALLAX V3 - MATCH REFERENCE \*/.*?/\* END HERO PARALLAX V3 \*/\n?',
    r'<script>\s*/\* HERO PARALLAX V3 RUNTIME \*/.*?</script>\s*',
    r'<script>\s*/\* hero system-only parallax \*/.*?</script>\s*',
    r'<script>\s*/\* advanced parallax only for the hero: layered system network \+ mouse \+ scroll \+ ambient drift \*/.*?</script>\s*',
]
for pat in patterns:
    s = re.sub(pat, '\n', s, flags=re.S)

css = r'''
/* HERO PARALLAX V6 - TRACE OF GENERATED REFERENCE */
.hero{
  isolation:isolate;
  overflow:hidden;
  perspective:1900px;
}
.hero>.hero-bg{z-index:0!important}
.hero>.wrap{position:relative;z-index:20}
.hero-system-parallax,.hero-advanced-parallax,.hero-parallax-v3,.hero-parallax-v4,.hero-parallax-exact{display:none!important}

/* Main CentralOS board: dominant foreground object, as in the generated reference. */
.hero .command{
  position:relative;
  z-index:30;
  isolation:isolate;
  transform-style:preserve-3d;
  will-change:transform;
}
.hero .os-window{
  z-index:5;
  box-shadow:0 48px 120px rgba(0,0,0,.62),0 0 36px rgba(255,91,0,.035);
}
.hero .float{
  z-index:90!important;
  transform-style:preserve-3d;
  will-change:transform;
}
.hero .float.a{z-index:100!important;right:-1%!important;top:4%!important}
.hero .float.b{z-index:100!important;left:-3%!important;bottom:4%!important}

.hero-reference-scene{
  position:absolute;
  inset:0;
  z-index:4;
  pointer-events:none;
  overflow:hidden;
  perspective:1900px;
  transform-style:preserve-3d;
}
.href-layer{position:absolute;inset:-3%;will-change:transform;transform-style:preserve-3d}

/* The reference is dark glass with sparse orange architecture; no grid, rings or node web. */
.href-ambient{
  background:
    radial-gradient(ellipse at 74% 18%,rgba(255,91,0,.10),transparent 17%),
    radial-gradient(ellipse at 97% 53%,rgba(255,91,0,.095),transparent 18%),
    radial-gradient(ellipse at 70% 91%,rgba(255,91,0,.065),transparent 18%),
    linear-gradient(90deg,rgba(0,0,0,.08),rgba(0,0,0,0) 35%,rgba(0,0,0,.03));
}

/* Large blurred interface slabs that sit behind the hero, matched to the concept positions. */
.href-panel{
  position:absolute;
  width:min(19vw,300px);
  height:min(14vw,148px);
  min-width:210px;
  min-height:105px;
  border:1px solid rgba(255,255,255,.07);
  border-radius:20px;
  background:linear-gradient(145deg,rgba(19,24,30,.26),rgba(7,9,12,.08));
  box-shadow:0 28px 80px rgba(0,0,0,.28),inset 0 1px rgba(255,255,255,.018),0 0 26px rgba(255,91,0,.014);
  backdrop-filter:blur(7px);
  opacity:.24;
  overflow:hidden;
  filter:blur(.25px);
}
.href-panel .pi{
  position:absolute;left:24px;top:22px;width:42px;height:42px;
  border:1px solid rgba(255,255,255,.065);border-radius:11px;
  display:grid;place-items:center;color:rgba(210,216,224,.24);font-size:21px
}
.href-panel .pt{position:absolute;left:82px;top:27px;color:rgba(216,221,227,.30);font:700 14px Manrope,sans-serif}
.href-panel .pb{position:absolute;left:82px;height:8px;border-radius:8px;background:rgba(137,146,156,.09)}
.href-panel .pb.a{top:58px;width:118px}.href-panel .pb.b{top:79px;width:78px}

/* Exact visual placement from the generated reference image. */
.href-client{left:2.4%;top:9.7%;transform:rotate(7deg)}
.href-budget{left:48.3%;top:9.2%;transform:rotate(2.5deg)}
.href-deadline{right:-4.6%;top:6.4%;transform:rotate(6deg)}
.href-parts{left:46.1%;bottom:3.0%;transform:rotate(-3.5deg)}
.href-delivery{right:-2.7%;bottom:2.5%;transform:rotate(5deg)}

/* Two huge almost invisible slabs behind the text/board, like the original concept. */
.href-ghost{
  position:absolute;border:1px solid rgba(255,255,255,.03);border-radius:30px;
  background:linear-gradient(145deg,rgba(17,21,27,.13),rgba(6,8,11,.045));
  box-shadow:0 42px 120px rgba(0,0,0,.24);opacity:.16;filter:blur(.8px)
}
.href-g1{left:21%;top:24%;width:34%;height:31%;transform:rotate(-3deg)}
.href-g2{left:53%;top:23%;width:42%;height:43%;transform:rotate(2deg);opacity:.10}
.href-ghost:before{
  content:"";position:absolute;left:7%;top:13%;width:56%;height:9px;border-radius:9px;
  background:rgba(255,255,255,.025);box-shadow:0 30px 0 rgba(255,255,255,.017),0 60px 0 rgba(255,255,255,.011)
}

/* Orange rails: same sparse, long, architectural lines seen in the concept. */
.href-rail{position:absolute;display:block;opacity:.48;filter:drop-shadow(0 0 7px rgba(255,91,0,.22))}
.href-v1{left:73.2%;top:6.6%;width:1px;height:77%;background:linear-gradient(180deg,rgba(255,91,0,0),rgba(255,91,0,.16) 7%,rgba(255,91,0,.88) 45%,rgba(255,91,0,.15) 87%,rgba(255,91,0,0))}
.href-v2{right:4.6%;top:18%;width:1px;height:66%;background:linear-gradient(180deg,transparent,rgba(255,91,0,.11),rgba(255,91,0,.74),rgba(255,91,0,.08),transparent)}
.href-h1{left:61.5%;top:8.3%;width:24%;height:1px;background:linear-gradient(90deg,transparent,rgba(255,91,0,.14),rgba(255,91,0,.54),transparent);transform:rotate(13deg);transform-origin:left center}
.href-h2{left:49.2%;top:50.8%;width:47%;height:1px;background:linear-gradient(90deg,transparent,rgba(255,91,0,.12),rgba(255,91,0,.38),transparent);transform:rotate(-1deg)}
.href-h3{left:48%;bottom:10.4%;width:45%;height:1px;background:linear-gradient(90deg,transparent,rgba(255,91,0,.12),rgba(255,91,0,.48),transparent);transform:rotate(5.5deg)}
.href-dash{position:absolute;left:61.8%;top:8.1%;width:255px;height:2px;background:repeating-linear-gradient(90deg,rgba(255,91,0,.62) 0 5px,transparent 5px 12px);transform:rotate(13deg);transform-origin:left center;opacity:.46;filter:drop-shadow(0 0 5px rgba(255,91,0,.22))}

.href-glow{position:absolute;right:-8%;top:22%;width:470px;height:590px;background:radial-gradient(ellipse,rgba(255,91,0,.105),rgba(255,91,0,.025) 45%,transparent 72%);filter:blur(20px);opacity:.74}
.href-dot{position:absolute;width:6px;height:6px;border-radius:50%;background:#ff6110;box-shadow:0 0 15px rgba(255,91,0,.88);opacity:.55;animation:hrefPulse 3.8s ease-in-out infinite}
.href-dot.d2{animation-delay:-1.25s}.href-dot.d3{animation-delay:-2.45s}
@keyframes hrefPulse{0%,100%{opacity:.20;transform:scale(.7)}50%{opacity:.86;transform:scale(1.25)}}

/* Dark-left mask from the reference so the typography remains clean while depth lives on the right. */
.href-mask{position:absolute;inset:0;z-index:15;background:linear-gradient(90deg,rgba(8,10,13,.92) 0%,rgba(8,10,13,.82) 29%,rgba(8,10,13,.42) 44%,rgba(8,10,13,.05) 63%,rgba(8,10,13,.08) 82%,rgba(8,10,13,.17) 100%)}

@media(max-width:900px){
  .hero-reference-scene{inset:0 -24% 0 0}
  .href-client,.href-budget,.href-g1{display:none}
  .href-deadline{right:2%;top:6%}
  .href-parts{left:auto;right:40%;bottom:2%}
  .href-delivery{right:1%;bottom:2%}
  .href-mask{background:linear-gradient(180deg,rgba(8,10,13,.30),rgba(8,10,13,.62))}
  .hero .float.a{right:1%!important;top:2%!important}
  .hero .float.b{left:0!important;bottom:2%!important}
}
@media(prefers-reduced-motion:reduce){.href-dot{animation:none!important}}
/* END HERO PARALLAX V6 */
'''

runtime = r'''
<script>
/* HERO PARALLAX V6 RUNTIME */
(()=>{
  const hero=document.querySelector('.hero');
  if(!hero || hero.querySelector('.hero-reference-scene')) return;
  hero.querySelectorAll('.hero-system-parallax,.hero-advanced-parallax,.hero-parallax-v3,.hero-parallax-v4,.hero-parallax-exact').forEach(el=>el.remove());

  const scene=document.createElement('div');
  scene.className='hero-reference-scene';
  scene.setAttribute('aria-hidden','true');
  scene.innerHTML=`
    <div class="href-layer href-ambient" data-depth="0.035"></div>
    <div class="href-layer" data-depth="0.055">
      <div class="href-ghost href-g1"></div><div class="href-ghost href-g2"></div>
      <div class="href-panel href-client"><span class="pi">♙</span><b class="pt">Cliente</b><i class="pb a"></i><i class="pb b"></i></div>
      <div class="href-panel href-budget"><span class="pi">⌕</span><b class="pt">Orçamento</b><i class="pb a"></i><i class="pb b"></i></div>
      <div class="href-panel href-deadline"><span class="pi">◷</span><b class="pt">Prazo</b><i class="pb a"></i><i class="pb b"></i></div>
      <div class="href-panel href-parts"><span class="pi">⚙</span><b class="pt">Peças</b><i class="pb a"></i><i class="pb b"></i></div>
      <div class="href-panel href-delivery"><span class="pi">◇</span><b class="pt">Entrega</b><i class="pb a"></i><i class="pb b"></i></div>
    </div>
    <div class="href-layer" data-depth="0.11">
      <i class="href-rail href-v1"></i><i class="href-rail href-v2"></i><i class="href-rail href-h1"></i><i class="href-rail href-h2"></i><i class="href-rail href-h3"></i><i class="href-dash"></i><i class="href-glow"></i>
    </div>
    <div class="href-layer" data-depth="0.17">
      <i class="href-dot" style="left:63%;top:11%"></i>
      <i class="href-dot d2" style="left:73.2%;top:31%"></i>
      <i class="href-dot d3" style="left:94.5%;top:29%"></i>
      <i class="href-dot d2" style="left:77%;top:79%"></i>
      <i class="href-dot" style="left:97%;top:57%"></i>
    </div>
    <div class="href-mask"></div>`;

  const bg=hero.querySelector('.hero-bg');
  if(bg) bg.insertAdjacentElement('afterend',scene); else hero.prepend(scene);

  if(matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const layers=[...scene.querySelectorAll('.href-layer')];
  const command=hero.querySelector('.command');
  const floatA=hero.querySelector('.float.a');
  const floatB=hero.querySelector('.float.b');
  let tx=0,ty=0,mx=0,my=0,ts=0,ss=0,last=performance.now();

  const readScroll=()=>{
    const r=hero.getBoundingClientRect();
    const vh=innerHeight||1;
    ts=Math.max(-1,Math.min(1,(vh*.45-r.top)/vh));
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
    const dt=Math.min(42,now-last);last=now;
    const ease=1-Math.pow(.0018,dt/1000);
    mx+=(tx-mx)*ease;my+=(ty-my)*ease;ss+=(ts-ss)*ease;

    layers.forEach((layer,i)=>{
      const d=Number(layer.dataset.depth||.05);
      const x=mx*105*d;
      const y=my*64*d-ss*148*d;
      layer.style.transform=`translate3d(${x}px,${y}px,${d*180}px)`;
    });

    if(command){
      command.style.transform=`translate3d(${mx*8}px,${my*5-ss*10}px,0) rotateY(${mx*0.45}deg) rotateX(${-my*0.3}deg)`;
    }
    if(floatA){
      floatA.style.transform=`translate3d(${-mx*15}px,${-my*9-ss*4}px,110px)`;
    }
    if(floatB){
      floatB.style.transform=`translate3d(${mx*12}px,${my*7-ss*5}px,110px)`;
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
})();
</script>
'''

if '</style>' not in s:
    raise SystemExit('style end not found')
s = s.replace('</style>', css + '\n</style>', 1)

if '</body>' not in s:
    raise SystemExit('body end not found')
s = s.replace('</body>', runtime + '\n</body>', 1)

p.write_text(s, encoding='utf-8')
print('patched landing.html to generated-reference trace v6')
