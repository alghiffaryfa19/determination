import QtQuick
Canvas {
    id:f
    property color fill: Theme.primary
    property int lobes: 10
    property real depth: 0.08
    onFillChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c=getContext("2d"); c.reset(); c.clearRect(0,0,width,height);
        c.beginPath();
        for(let i=0;i<=360;i++) {
            const a=i*Math.PI/180;
            const r=Math.min(width,height)*(.46+depth*.5*Math.cos(lobes*a));
            const x=width/2+Math.cos(a)*r; const y=height/2+Math.sin(a)*r;
            if(i===0)c.moveTo(x,y);else c.lineTo(x,y);
        }
        c.closePath(); c.fillStyle=fill; c.fill();
    }
}
