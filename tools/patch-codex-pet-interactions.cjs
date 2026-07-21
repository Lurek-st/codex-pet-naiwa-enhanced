const fs = require("node:fs");
const path = require("node:path");

const root = process.argv[2];
if (!root) {
  throw new Error("usage: node patch-codex-pet-interactions.cjs <extracted-asar>");
}

function findSingle(directory, pattern) {
  const matches = fs
    .readdirSync(directory)
    .filter((name) => pattern.test(name))
    .map((name) => path.join(directory, name));
  if (matches.length !== 1) {
    throw new Error(
      `expected exactly one ${pattern} in ${directory}, found ${matches.length}`,
    );
  }
  return matches[0];
}

function findSingleContaining(directory, pattern, needles) {
  const matches = fs
    .readdirSync(directory)
    .filter((name) => pattern.test(name))
    .map((name) => path.join(directory, name))
    .filter((file) => {
      const source = fs.readFileSync(file, "utf8");
      return needles.some((needle) => source.includes(needle));
    });
  if (matches.length !== 1) {
    throw new Error(
      `expected exactly one ${pattern} containing a pet-loader marker in ${directory}, found ${matches.length}`,
    );
  }
  return matches[0];
}

function count(source, needle) {
  return source.split(needle).length - 1;
}

function replaceOnce(source, before, after, label) {
  const beforeCount = count(source, before);
  const afterCount = count(source, after);
  if (beforeCount === 1 && afterCount === 0) {
    return { source: source.replace(before, after), result: `${label}=patched` };
  }
  if (beforeCount === 0 && afterCount === 1) {
    return { source, result: `${label}=already-patched` };
  }
  throw new Error(
    `${label}: expected before=1/after=0 or before=0/after=1, got before=${beforeCount} after=${afterCount}`,
  );
}

function replaceAnyOnce(source, beforeAny, after, label) {
  const beforeCounts = beforeAny.map((before) => count(source, before));
  const beforeCount = beforeCounts.reduce((total, value) => total + value, 0);
  const afterCount = count(source, after);
  if (beforeCount === 1 && afterCount === 0) {
    const before = beforeAny[beforeCounts.findIndex((value) => value === 1)];
    return { source: source.replace(before, after), result: `${label}=patched` };
  }
  if (beforeCount === 0 && afterCount === 1) {
    return { source, result: `${label}=already-patched` };
  }
  throw new Error(
    `${label}: expected one legacy/current before variant or one final after marker, got before=[${beforeCounts.join(",")}] after=${afterCount}`,
  );
}

function patchFile(file, replacements) {
  let source = fs.readFileSync(file, "utf8");
  const results = [];
  for (const replacement of replacements) {
    const patched = replacement.beforeAny
      ? replaceAnyOnce(
          source,
          replacement.beforeAny,
          replacement.after,
          replacement.label,
        )
      : replaceOnce(
          source,
          replacement.before,
          replacement.after,
          replacement.label,
        );
    source = patched.source;
    results.push(patched.result);
  }
  fs.writeFileSync(file, source, "utf8");
  return results;
}

const assets = path.join(root, "webview", "assets");
const build = path.join(root, ".vite", "build");
const nativePage = findSingle(assets, /^avatar-overlay-native-page-.*\.js$/);
const nativeFrame = findSingle(assets, /^avatar-overlay-native-frame-.*\.js$/);
const activityModel = findSingle(
  assets,
  /^avatar-overlay-pill-material\.module-.*\.js$/,
);
const overlaySelection = findSingle(
  assets,
  /^use-avatar-overlay-selection-.*\.js$/,
);
const codexAvatar = findSingle(assets, /^codex-avatar-.*\.js$/);
const avatarSpritesheet = findSingle(assets, /^avatar-spritesheet-.*\.js$/);
const main = findSingle(build, /^main-.*\.js$/);
const petLoader = findSingleContaining(build, /^src-.*\.js$/, [
  "RY=1536,zY=1872,BY=2288,VY=80,HY=W({id:",
  "RY=1536,zY=1872,BY=2288,CODEX_PET_V3_HEIGHT=2496,VY=80,HY=W({id:",
]);

const results = [];

results.push(
  ...patchFile(nativePage, [
    {
      label: "custom-pet-renderer-drag-request",
      beforeAny: [
        "pointerWindowX:e.clientX,pointerWindowY:e.clientY,usesOrbPhysics:t})",
        "pointerWindowX:e.clientX,pointerWindowY:e.clientY,usesOrbPhysics:t,forceRendererDrag:g.id===`nailong-dev`})",
      ],
      after:
        "pointerWindowX:e.clientX,pointerWindowY:e.clientY,usesOrbPhysics:t,forceRendererDrag:g.id===`nailong-dev`||g.id===`custom:naifrog-dev`})",
    },
  ]),
);

results.push(
  ...patchFile(main, [
    {
      label: "drag-message-flag-forwarding",
      before:
        "let r=PN(n),i=r==null?{pointerWindowX:n.pointerWindowX,pointerWindowY:n.pointerWindowY}:{...r,pointerWindowX:n.pointerWindowX,pointerWindowY:n.pointerWindowY};e.startDrag(t.id,i,n.usesOrbPhysics??!1);",
      after:
        "let r=PN(n),i=r==null?{pointerWindowX:n.pointerWindowX,pointerWindowY:n.pointerWindowY,forceRendererDrag:n.forceRendererDrag===!0}:{...r,pointerWindowX:n.pointerWindowX,pointerWindowY:n.pointerWindowY,forceRendererDrag:n.forceRendererDrag===!0};e.startDrag(t.id,i,n.usesOrbPhysics??!1);",
    },
    {
      label: "custom-pet-native-drag-bypass",
      before:
        "this.windowServerDragActive=this.layoutMode===`native`&&!n&&this.compositionHost.performWindowDrag()",
      after:
        "this.windowServerDragActive=this.layoutMode===`native`&&!n&&!t.forceRendererDrag&&this.compositionHost.performWindowDrag()",
    },
  ]),
);

results.push(
  ...patchFile(activityModel, [
    {
      label: "active-tool-state-detection",
      before:
        "d=c?Me(e):je(e,r),p=t&&s===`waiting`?re(e):null;return{actionPath:`/local/`+e.id,controlTarget:{type:`app-server-conversation`,conversationId:e.id},hostId:a,key:o+`:`+a+`:`+e.id,localConversationId:e.id,source:o,showInNotificationTray:",
      after:
        "d=c?Me(e):je(e,r),p=t&&s===`waiting`?re(e):null,m=(l(e)?.items??[]).some(e=>(e.type===`commandExecution`||e.type===`fileChange`||e.type===`mcpToolCall`||e.type===`webSearch`)&&e.status===`inProgress`);return{actionPath:`/local/`+e.id,controlTarget:{type:`app-server-conversation`,conversationId:e.id},hostId:a,isToolActive:m,key:o+`:`+a+`:`+e.id,localConversationId:e.id,source:o,showInNotificationTray:",
    },
  ]),
);

results.push(
  ...patchFile(overlaySelection, [
    {
      label: "tool-state-notification-fingerprint",
      before:
        "e.level,e.isLoading?`loading`:`done`,e.action?.path??``,e.waitingRequest",
      after:
        "e.level,e.isLoading?`loading`:`done`,e.isToolActive?`tool-active`:`tool-idle`,e.action?.path??``,e.waitingRequest",
    },
    {
      label: "tool-state-notification-forwarding",
      before:
        "id:e.key,isLoading:e.status===`running`,kind:`session`,level:P(e.status)",
      after:
        "id:e.key,isLoading:e.status===`running`,isToolActive:e.isToolActive===!0,kind:`session`,level:P(e.status)",
    },
  ]),
);

results.push(
  ...patchFile(avatarSpritesheet, [
    {
      label: "custom-pet-twelve-row-layout",
      before: "n={1:9,2:11}",
      after: "n={1:9,2:11,3:12}",
    },
  ]),
);

results.push(
  ...patchFile(petLoader, [
    {
      label: "custom-pet-v3-height-constant",
      before: "RY=1536,zY=1872,BY=2288,VY=80,HY=W({id:",
      after:
        "RY=1536,zY=1872,BY=2288,CODEX_PET_V3_HEIGHT=2496,VY=80,HY=W({id:",
    },
    {
      label: "custom-pet-v3-manifest-schema",
      before: "spriteVersionNumber:sd([K(1),K(2)]).default(1)",
      after: "spriteVersionNumber:sd([K(1),K(2),K(3)]).default(1)",
    },
    {
      label: "custom-pet-v3-sheet-validation",
      before: "let n=XY(e),r=t===1?zY:BY;",
      after:
        "let n=XY(e),r=t===1?zY:t===3?CODEX_PET_V3_HEIGHT:BY;",
    },
  ]),
);

results.push(
  ...patchFile(codexAvatar, [
    {
      label: "waiting-uses-eight-typing-frames",
      before: "waving:j(3,4,140,280),waiting:j(6,6,150,260)",
      after: "waving:j(3,4,140,280),waiting:j(6,8,110,180)",
    },
    {
      label: "typing-animation-row",
      before:
        "review:j(8,6,150,280),running:j(7,6,120,220),\"running-left\":j(2,8,120,220)",
      after:
        "review:j(8,6,150,280),running:j(7,6,120,220),typing:j(11,8,110,180),\"running-left\":j(2,8,120,220)",
    },
    {
      label: "custom-pet-hover-loop-animation-row",
      before:
        "z={failed:j(5,8,140,240),idle:L,jumping:j(4,5,140,280),review:",
      after:
        "z={failed:j(5,8,140,240),idle:L,jumping:j(4,5,140,280),\"jumping-loop\":j(4,5,140,280),review:",
    },
    {
      label: "custom-pet-hover-loop-animation-policy",
      before:
        "if(e===`idle`)return{frames:R,loopStartIndex:0};let r=[...n,...n,...n];",
      after:
        "if(e===`idle`)return{frames:R,loopStartIndex:0};if(e===`jumping-loop`)return{frames:n,loopStartIndex:0};let r=[...n,...n,...n];",
    },
  ]),
);

results.push(
  ...patchFile(nativeFrame, [
    {
      label: "custom-pet-hover-hitbox",
      beforeAny: [
        "style:{height:Se.height,left:Se.left,top:Se.top,width:Se.width}",
        "style:{height:Se.height+(r.id===`nailong-dev`?24:0),left:Se.left-(r.id===`nailong-dev`?12:0),top:Se.top-(r.id===`nailong-dev`?12:0),width:Se.width+(r.id===`nailong-dev`?24:0)}",
        "style:{height:Se.height+(r.id===`nailong-dev`?72:0),left:Se.left-(r.id===`nailong-dev`?12:0),top:Se.top-(r.id===`nailong-dev`?12:0),width:Se.width+(r.id===`nailong-dev`?24:0)}",
      ],
      after:
        "style:{height:Se.height+((r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)?72:0),left:Se.left-((r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)?12:0),top:Se.top-((r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)?12:0),width:Se.width+((r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)?24:0)}",
    },
    {
      label: "custom-pet-hover-visual-centering",
      beforeAny: [
        '"data-avatar-overlay-hit-region":xe===`hidden`?void 0:`mascot`,className:`h-full w-full`',
        '"data-avatar-overlay-hit-region":xe===`hidden`?void 0:`mascot`,className:C(`h-full w-full`,r.id===`nailong-dev`&&`flex items-center justify-center`)',
        '"data-avatar-overlay-hit-region":xe===`hidden`?void 0:`mascot`,className:C(`h-full w-full`,r.id===`nailong-dev`&&`flex items-start justify-center pt-3`)',
      ],
      after:
        '"data-avatar-overlay-hit-region":xe===`hidden`?void 0:`mascot`,className:C(`h-full w-full`,(r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)&&`flex items-start justify-center pt-3`)',
    },
    {
      label: "custom-pet-typing-state",
      beforeAny: [
        "spritesheetUrl:r.spritesheetUrl,state:_e.mascotState,style:p,",
        "spritesheetUrl:r.spritesheetUrl,state:r.id===`nailong-dev`&&_[0]?.isToolActive===!0?`typing`:_e.mascotState,style:p,",
      ],
      after:
        "spritesheetUrl:r.spritesheetUrl,state:(r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)&&(_[0]?.isToolActive===!0||_e.mascotState===`running`)?`typing`:_e.mascotState,style:p,",
    },
    {
      label: "custom-pet-typing-row-count",
      beforeAny: [
        "spriteVersionNumber:r.spriteVersionNumber,spritesheetUrl:r.spritesheetUrl,state:",
        "spriteVersionNumber:r.id===`nailong-dev`?3:r.spriteVersionNumber,spritesheetUrl:r.spritesheetUrl,state:",
      ],
      after:
        "spriteVersionNumber:(r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)?3:r.spriteVersionNumber,spritesheetUrl:r.spritesheetUrl,state:",
    },
    {
      label: "custom-pet-laugh-audio-ref",
      beforeAny: [
        "le=(0,Q.useRef)(null),[ue,de]=(0,Q.useState)(!1)",
        "le=(0,Q.useRef)(null),nailongLaughAudioRef=(0,Q.useRef)(null),[ue,de]=(0,Q.useState)(!1)",
      ],
      after:
        "le=(0,Q.useRef)(null),nailongLaughAudioRef=(0,Q.useRef)(null),[nailongLaughing,setNailongLaughing]=(0,Q.useState)(!1),[ue,de]=(0,Q.useState)(!1)",
    },
    {
      label: "custom-pet-laugh-audio-lifecycle",
      before:
        "ke=u.tray==null||q?.type===`native-root`?void 0:Math.max(0,u.tray.height),Ae=()=>{",
      after:
        "ke=u.tray==null||q?.type===`native-root`?void 0:Math.max(0,u.tray.height),stopNailongLaugh=()=>{let e=nailongLaughAudioRef.current;e!=null&&(e.pause(),e.currentTime=0)},startNailongLaugh=()=>{if(r.id!==`nailong-dev`&&r.id!==`custom:naifrog-dev`)return;let e=nailongLaughAudioRef.current;e==null&&(e=new Audio(new URL(`./nailong-laugh.mp3`,import.meta.url).href),e.loop=!0,e.volume=.65,nailongLaughAudioRef.current=e),e.currentTime=0,e.play().catch(()=>{})},Ae=()=>{",
    },
    {
      label: "custom-pet-laugh-audio-cleanup",
      before:
        "()=>{se.current=!0,le.current!=null&&window.clearTimeout(le.current)}),[]);let Ne;",
      after:
        "()=>{se.current=!0,le.current!=null&&window.clearTimeout(le.current),stopNailongLaugh(),nailongLaughAudioRef.current=null}),[r?.id]);let Ne;",
    },
    {
      label: "custom-pet-laugh-audio-hover-events",
      beforeAny: [
        "onPointerEnter:Ae,onPointerLeave:je,children:Pe",
        "onPointerEnter:e=>{Ae(e),startNailongLaugh()},onPointerLeave:e=>{je(e),stopNailongLaugh()},children:Pe",
      ],
      after:
        "onPointerEnter:e=>{Ae(e),setNailongLaughing(!0),startNailongLaugh()},onPointerLeave:e=>{je(e),setNailongLaughing(!1),stopNailongLaugh()},children:Pe",
    },
    {
      label: "custom-pet-laugh-audio-pointer-safety",
      beforeAny: [
        "onLostPointerCapture:O,onPointerCancel:ee,onPointerDown:k,onPointerMove:M,onPointerUp:N,children:",
        "onLostPointerCapture:e=>{stopNailongLaugh(),O(e)},onPointerCancel:e=>{stopNailongLaugh(),ee(e)},onPointerDown:e=>{stopNailongLaugh(),k(e)},onPointerMove:M,onPointerUp:e=>{N(e),e.currentTarget.matches(`:hover`)&&startNailongLaugh()},children:",
      ],
      after:
        "onLostPointerCapture:e=>{setNailongLaughing(!1),stopNailongLaugh(),O(e)},onPointerCancel:e=>{setNailongLaughing(!1),stopNailongLaugh(),ee(e)},onPointerDown:e=>{setNailongLaughing(!1),stopNailongLaugh(),k(e)},onPointerMove:M,onPointerUp:e=>{N(e),e.currentTarget.matches(`:hover`)&&(setNailongLaughing(!0),startNailongLaugh())},children:",
    },
    {
      label: "custom-pet-hover-loop-transient-state",
      beforeAny: [
        "style:p,transientState:d});return",
        "style:p,transientState:d??(r.id===`nailong-dev`&&nailongLaughing?`jumping-loop`:void 0)});return",
      ],
      after:
        "style:p,transientState:(r.id===`nailong-dev`||r.id===`custom:naifrog-dev`)&&nailongLaughing?`jumping-loop`:d});return",
    },
  ]),
);

for (const result of results) {
  console.log(result);
}
console.log(`native-page=${nativePage}`);
console.log(`native-frame=${nativeFrame}`);
console.log(`activity-model=${activityModel}`);
console.log(`overlay-selection=${overlaySelection}`);
console.log(`codex-avatar=${codexAvatar}`);
console.log(`avatar-spritesheet=${avatarSpritesheet}`);
console.log(`main=${main}`);
console.log(`pet-loader=${petLoader}`);
