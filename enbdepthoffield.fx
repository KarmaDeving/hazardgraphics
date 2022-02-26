
/* 

 * NaturalVision Evolved       by Razed
 * ENBSeries and focusing code by Boris Vorontsov
 * Depth of field shader       by icelaglace

 * Simple depth of field shader for gameplay usage
 * Sampling based on "Bokeh depth of field in a single pass"
 * https://bit.ly/3dtDWI9 

 ! Please ask permissions if you want to re-use the shader   !
 ! Please ask permissions if you want to port it to Reshade  !
 ! Credit people properly, thank you, even if it's on the web!

 -- You know who you are. I wouldn't have to type this if you didn't.

 */
bool    text0            
<
    string UIName="Near Field settings ---------------------------------------------------";
> = {false};

bool    NearFieldEnable             
<
    string UIName="Blur the near field toggle";
> = {true};

float   NearFieldPower
<
    string UIName="Near field intensity";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=1000.0;
> = {20.0};

bool    textmanu           
<
    string UIName="Manual DOF ---------------------------------------------------";
> = {false};


float   ManualFocusDistance
<
    string UIName="Manual Focus : Distance";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=1000.0;
> = {1.0};

float   ManualApertureSize
<
    string UIName="Manual Focus : Aperture";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=10.0;
> = {1.0};

float   ManualNearFieldPower
<
    string UIName="Manual Focus : Near field power";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=1000.0;
> = {20.0};

bool    textauto             
<
    string UIName="Auto-focus DOF ---------------------------------------------------";
> = {false};

float   ApertureSize
<
    string UIName="Auto-focus : Aperture";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=10.0;
> = {1.0};

float   FocusSpeed
<
    string UIName="Auto-focus : Speed";
    string UIWidget="spinner";
    float UIMin=0.01;
    float UIMax=100.0;
> = {10.0};

float   FocusRangeBoost
<
    string UIName="Auto-focus : Range boost";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=100.0;
> = {1.0};


float2  FocusLocation
<
    string UIName="Auto-focus : Point of interest";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=1.0;
> = {0.5, 0.3};

bool    textblur             
<
    string UIName="Blur Settings ---------------------------------------------------";
> = {false};

float   ChromaticSpread
<
    string UIName="Blur : Chromatic Spread";
    string UIWidget="spinner";
    float UIMin=1.0;
    float UIMax=32.0;
> = {16.0};


float   ExtraBlurSize
<
    string UIName="Blur : Size";
    string UIWidget="spinner";
    float UIMin=0.0;
    float UIMax=2.0;
> = {1.0};


int     BlurSteps
<
    string UIName="Blur : Quality Steps";
    string UIWidget="spinner";
    int UIMin=1;
    int UIMax=16;
> = {6};

bool    textdof            
<
    string UIName="Quality Settings ---------------------------------------------------";
> = {false};


float   MaxDOFSize
<
    string UIName="DOF : Maximum size";
    string UIWidget="spinner";
    float UIMin=2.0;
    float UIMax=20.0;
> = {20.0};


float   DOFQuality
<
    string UIName="DOF : Quality";
    string UIWidget="spinner";
    float UIMin=0.1;
    float UIMax=2.0;
> = {1.0};

float   DOFPerformance
<
    string UIName="DOF : Performance scaler";
    string UIWidget="spinner";
    float UIMin=0.1;
    float UIMax=1.0;
> = {1.0};

bool    textmouse            
<
    string UIName="Screenshot settings ---------------------------------------------------";
> = {false};

bool    ManualFocusMouse             
<
    string UIName="Mouse Click to focus toggle";
> = {false};


float4  tempInfo2;
float4  ScreenSize;
float4  DofParameters;

Texture2D TextureCurrent; 
Texture2D TexturePrevious;
Texture2D TextureColor;
Texture2D TextureDepth;
Texture2D TextureFocus;

Texture2D RenderTargetRGBA32; 
Texture2D RenderTargetRGBA64; 
Texture2D RenderTargetRGBA64F;
Texture2D RenderTargetR16F; 
Texture2D RenderTargetR32F; 
Texture2D RenderTargetRGB32F; 

SamplerState Sampler0
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};
SamplerState Sampler1
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VS_INPUT_POST
{
    float3 pos      : POSITION;
    float2 txcoord  : TEXCOORD0;
};
struct VS_OUTPUT_POST
{
    float4 pos      : SV_POSITION;
    float2 txcoord0 : TEXCOORD0;
};

VS_OUTPUT_POST  VS_Quad(VS_INPUT_POST IN)
{
    VS_OUTPUT_POST  OUT;
    float4  pos;
    pos.xyz=IN.pos.xyz;
    pos.w=1.0;
    OUT.pos=pos;
    OUT.txcoord0.xy=IN.txcoord.xy;
    return OUT;
}

#define MaxSize   MaxDOFSize
#define MaxRadius DOFQuality

float GetDepth(float D)
{
    return 1.0f - (1.0f / D);
}

float ComputeCoC(float theDepth, float theFocus, float theAperture, float theNearField)
{
    float factor = abs(theDepth - theFocus);
          factor = factor * (theAperture * 36.0f);

    if(theDepth < theFocus) 
          factor /= theNearField;

    if(!NearFieldEnable && theDepth < theFocus) 
          factor = 0.0f;

    return min(factor, 1.5f);
}

float GetBlurSize(float depth, float focusPoint, float focusScale)
{
    float coc = (1.0f / focusPoint - 1.0f / depth) * focusScale;
    return abs(coc) * 1e+4;
}

float3 GetDOF(float2 theUV, float theDepth, float theFocus)
{
    float weight = 1.0f; float mask = 0.0f;
    float radius = MaxRadius;

    float3 color = TextureColor.Sample(Sampler1, theUV).xyz;

    float coc     = RenderTargetR16F.Sample(Sampler0, theUV).x;
    float origcoc = GetBlurSize(theDepth, theFocus, coc);

    float2 pixelres = 1.0f / ScreenSize.x * coc; pixelres.y *= ScreenSize.z;

    for (float d = 0.0f; radius < MaxSize; d += 2.3999f)
    {
        float2 uv = theUV + float2(cos(d), sin(d)) * pixelres * radius;
        float3 dofcolor = TextureColor.Sample(Sampler1, uv).xyz;
        float dofdepth  = TextureDepth.Sample(Sampler0, uv).x;
        float dofcoc = GetBlurSize(dofdepth, theFocus, coc);
        
        if (dofdepth < theDepth) dofcoc = clamp(dofcoc, 0.0f, origcoc * 2.0f);

        mask    = smoothstep(radius - 0.5f, radius + 0.5f, dofcoc);
        color  += lerp(color / weight, dofcolor, mask);
        radius += MaxRadius / radius;
        weight += 1.0f;
    }

    color /= weight;
    return color;
}


float4  PS_Aperture(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    /* Aperture isn't useful for us.
     * Returns blank as we cannot disable the pass
     * Order is hard-coded in ENB */

    return float4(0.0f,0.0f,0.0f,0.0f);
}

// default ENB readfocus with some modifications to make it simpler
float4  PS_ReadFocus(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float4  res;
    float2  pos;
    float   curr=0.0;
    const float step=1.0/16.0;
    const float halfstep=0.5/16.0;
    pos.x=halfstep;
    for (int x=0; x<16; x++)
    {
        pos.y=halfstep;
        for (int y=0; y<16; y++)
        {
            float2  coord=pos.xy  * 0.05;
            coord+=IN.txcoord0.xy * (0.05 * FocusRangeBoost) + FocusLocation;
            float   tempcurr=TextureDepth.SampleLevel(Sampler0, coord, 0.0).x;
            curr+=tempcurr;
            pos.y+=step;
        }
        pos.x+=step;
    }
    curr*=1.0/(16.0*16.0);
    res=curr;
    res=max(res, 0.0);
    res=min(res, 1.0);

    if (ManualFocusMouse) 
        res = TextureDepth.Sample(Sampler0,tempInfo2.xy).x;
    
    return res;
}

// default ENB focus with some modifications to make it simpler
float4  PS_Focus(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float4  res;
    float   prev=TexturePrevious.Sample(Sampler0, IN.txcoord0.xy).x;
    float2  pos;
    float   curr=0.0;
    const float step=1.0/16.0;
    const float halfstep=0.5/16.0;
    pos.x=halfstep;
    for (int x=0; x<16; x++)
    {
        pos.y=halfstep;
        for (int y=0; y<16; y++)
        {
            float   tempcurr=TextureCurrent.Sample(Sampler0, IN.txcoord0.xy + pos.xy).x;
            curr+=tempcurr;
            pos.y+=step;
        }
        pos.x+=step;
    }
    curr*=1.0/(16.0*16.0);
    res=lerp(prev, curr, DofParameters.w * FocusSpeed);
    res=max(res, 0.0);
    res=min(res, 1.0);
    res.w=0.0;
    return res;
}

// CoC techniques
// 2 techniques, redundant but useful for the end-user
float4  PS_ComputeFactor(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float depth = TextureDepth.Sample(Sampler0, IN.txcoord0).x;
    float focus = TextureFocus.Sample(Sampler0, IN.txcoord0).x;
    float coc   = ComputeCoC(depth,focus,ApertureSize, NearFieldPower);
    return float4(coc, 0.0f, 0.0f, 0.0f);
}

float4  PS_ComputeFactorManual(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float depth = TextureDepth.Sample(Sampler0, IN.txcoord0).x; 
    float focus = 0.0f;

    if (ManualFocusMouse)
        focus = TextureFocus.Sample(Sampler0, IN.txcoord0).x;
    else
        focus = GetDepth(depth * (ManualFocusDistance * ManualFocusDistance));
   
    float coc   = ComputeCoC(depth,focus,ManualApertureSize, ManualNearFieldPower);
    return float4(coc, 0.0f, 0.0f, 0.0f);
}

// Create DOF
float4  PS_Dof(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float2 coord = IN.txcoord0.xy;
    clip(coord.x > DOFPerformance || coord.y > DOFPerformance ? -1 : 1);
    coord /= DOFPerformance;

    float  depth = TextureDepth.Sample(Sampler0, coord).x;
    float  focus = TextureFocus.Sample(Sampler0, coord).x;
    float3 color = GetDOF(coord,depth,focus);

    return float4(color.xyz,color.x);
}

float4  PS_DofManual(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{    
    float2 coord = IN.txcoord0.xy;
    clip(coord.x > DOFPerformance || coord.y > DOFPerformance ? -1 : 1);
    coord /= DOFPerformance;

    float depth = TextureDepth.Sample(Sampler0, coord).x;
    float focus = 0.0f;

    if (ManualFocusMouse)
        focus = TextureFocus.Sample(Sampler0, coord).x;
    else
        focus = GetDepth(depth * (ManualFocusDistance * ManualFocusDistance));

    float3 color = GetDOF(coord,depth,focus);

    return float4(color.xyz,1.0f);
}

// Final technique for extra blur
// Taken from iCEnhancer 3.0 DOF
float4  PS_Dof2(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
    float2 coord     = IN.txcoord0.xy;
    float2 centeruv  = coord * 2.0f - 1.0f;

    float3 color     = RenderTargetRGB32F.Sample(Sampler1, (centeruv * 0.5f + 0.5f) * DOFPerformance).xyz;
    float  coc       = RenderTargetR16F.Sample(Sampler0, IN.txcoord0.xy).x;
    float3 origcolor = TextureColor.Sample(Sampler1, IN.txcoord0.xy).xyz;

    float  scale        = (coc * ExtraBlurSize) / DOFPerformance;

    float3 chromapower  = float3(-1.0f, 0.0f, 1.0f) * ChromaticSpread * DOFPerformance;
           chromapower /= ScreenSize.x;
           chromapower *= scale;
           chromapower++;
    
    if (DOFPerformance <= 0.999f)
           chromapower = 1.0f;

    int steps = BlurSteps;

    for(int i = 0; i < steps; i++)
    {
        float d = (float)i; 
        d *= (3.1415f * 2.0f) / (float)steps;
        float2 dir = float2(cos(d), sin(d));
        dir.y *= ScreenSize.z;
        color.x += RenderTargetRGB32F.Sample(Sampler1, (chromapower.x * centeruv * 0.5f + 0.5f + (dir / ScreenSize.x) * 2.0f * scale) * DOFPerformance).x;
        color.y += RenderTargetRGB32F.Sample(Sampler1, (chromapower.y * centeruv * 0.5f + 0.5f + (dir / ScreenSize.x) * 2.0f * scale) * DOFPerformance).y;
        color.z += RenderTargetRGB32F.Sample(Sampler1, (chromapower.z * centeruv * 0.5f + 0.5f + (dir / ScreenSize.x) * 2.0f * scale) * DOFPerformance).z;
    }

    color /= steps + 1.0f;
  
    if (DOFPerformance <= 0.999f)
    {
        color = lerp(origcolor,color,smoothstep(0.0, 0.1, saturate(abs(coc))));
    }

    return float4(color.xyz,1);
}

technique11 Aperture
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Aperture()));
    }
}

technique11 ReadFocus
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_ReadFocus()));
    }
}

technique11 Focus
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Focus()));
    }
}

technique11 Dof <string UIName="Gameplay DOF Auto-focus"; string RenderTarget="RenderTargetR16F";>
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_ComputeFactor()));
    }
}

technique11 Dof1 <string RenderTarget="RenderTargetRGB32F";>
{    
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Aperture()));
    }  
    pass p1
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Dof()));
    }
}

technique11 Dof2
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Dof2()));
    }
}

technique11 DofManual <string UIName="Gameplay DOF Manual"; string RenderTarget="RenderTargetR16F";>
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_ComputeFactorManual()));
    }
}

technique11 DofManual1 <string RenderTarget="RenderTargetRGB32F";>
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Aperture()));
    }  
    pass p1
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_DofManual()));
    }
}

technique11 DofManual2
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
        SetPixelShader(CompileShader(ps_5_0, PS_Dof2()));
    }
}


