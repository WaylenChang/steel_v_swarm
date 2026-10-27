// Compile only the original image-fetch, display-style and raw sampling program.
// It does not construct a world or supply a substitute classifier.
export function worldImagerySource(terrain,data,grabFn,grabBlock,grabConst) {
  const line=(text,prefix)=>{
    const found=text.split('\n').find(value=>value.startsWith(prefix));
    if(!found)throw new Error('Original imagery source seam missing: '+prefix);
    return found.replace(/^export /,'');
  };
  const body=grabBlock(terrain,'sampleColor = (x, z, validOnly = false) =>');
  const boundary=body.indexOf('if (px < 0 || py < 0 || px >= iw || py >= ih)');
  if(boundary<0)throw new Error('Original raw imagery bounds seam missing');
  return [
    grabConst(data,'MAPGEO'),line(data,'export const ROUTE_EDGE_MARGIN_M ='),
    line(data,'const R_EARTH_M ='),line(data,'export const mapRot ='),
    grabFn(data,'rotXZ'),grabFn(data,'xzToLL'),grabFn(data,'llToXZ'),
    grabFn(data,'battleRect'),grabFn(data,'battleBBox'),
    line(terrain,'const d2r ='),line(terrain,'const IMAGERY ='),
    ...['lon2tx','lat2ty','loadImage','fetchImagery','stylizeImagery'].map(name=>grabFn(terrain,name)),
    `return {fetchImagery,stylizeImagery,llToXZ,battleRect,battleBBox,
      sampler(center,imagery,idata) {
        const iw=imagery.canvas.width,ih=imagery.canvas.height;
        return (x,z,validOnly=false)=>${body};
      },
      project(center,imagery,x,z) ${body.slice(0,boundary)}return [lat,lng,px,py];},
      constants(center) {
        return {latitude:center.lat,longitude:center.lng,rotation:mapRot(center),
          cosine:Math.cos(-mapRot(center)),sine:Math.sin(-mapRot(center)),
          latitudeCosine:Math.cos(center.lat*Math.PI/180),
          realScale:MAPGEO.REAL_SCALE,earthRadius:R_EARTH_M,pi:Math.PI};
      }
    };`,
  ].join('\n');
}
