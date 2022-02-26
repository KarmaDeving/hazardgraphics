/* 

 * NaturalVision Evolved by Razed
 * ENBSeries             by Boris Vorontsov
 * Modifications         by icelaglace 
 * CAS shader            by AMD and based on SLSNe port for ReShade
 * SMAA shader           by Jorge Jimenez, Jose I. Echevarria, Belen Masia, Fernando Navarro, Diego Gutierrez, ported to ENB by Kingeric1992
 * Copyright (c) 2020 Advanced Micro Devices, Inc. All rights reserved. Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 ! Please ask permissions if you want to re-use the shader    !
 ! Credit people properly, thank you, even if it's on the web !

 -- You know who you are. I wouldn't have to type this if you didn't.

 */

float	ESharpAmount
<
	string UIName="Sharp:: amount";
	string UIWidget="spinner";
	float UIMin=0.0;
	float UIMax=10.0;
> = {1.0};

//+++++++++++++++++++++++++++++
//external enb parameters, do not modify
//+++++++++++++++++++++++++++++
//x = generic timer in range 0..1, period of 16777216 ms (4.6 hours), y = average fps, w = frame time elapsed (in seconds)
float4	Timer;
//x = Width, y = 1/Width, z = aspect, w = 1/aspect, aspect is Width/Height
float4	ScreenSize;
//changes in range 0..1, 0 means full quality, 1 lowest dynamic quality (0.33, 0.66 are limits for quality levels)
float	AdaptiveQuality;
//x = current weather index, y = outgoing weather index, z = weather transition, w = time of the day in 24 standart hours. Weather index is value from weather ini file, for example WEATHER002 means index==2, but index==0 means that weather not captured.
float4	Weather;
//x = dawn, y = sunrise, z = day, w = sunset. Interpolators range from 0..1
float4	TimeOfDay1;
//x = dusk, y = night. Interpolators range from 0..1
float4	TimeOfDay2;
//changes in range 0..1, 0 means that night time, 1 - day time
float	ENightDayFactor;
//changes 0 or 1. 0 means that exterior, 1 - interior
float	EInteriorFactor;

//+++++++++++++++++++++++++++++
//external enb debugging parameters for shader programmers, do not modify
//+++++++++++++++++++++++++++++
//keyboard controlled temporary variables. Press and hold key 1,2,3...8 together with PageUp or PageDown to modify. By default all set to 1.0
float4	tempF1; //0,1,2,3
float4	tempF2; //5,6,7,8
float4	tempF3; //9,0
// xy = cursor position in range 0..1 of screen;
// z = is shader editor window active;
// w = mouse buttons with values 0..7 as follows:
//    0 = none
//    1 = left
//    2 = right
//    3 = left+right
//    4 = middle
//    5 = left+middle
//    6 = right+middle
//    7 = left+right+middle (or rather cat is sitting on your mouse)
float4	tempInfo1;
// xy = cursor position of previous left mouse button click
// zw = cursor position of previous right mouse button click
float4	tempInfo2;



//+++++++++++++++++++++++++++++
//mod parameters, do not modify
//+++++++++++++++++++++++++++++
Texture2D			TextureOriginal; //color R10B10G10A2 32 bit ldr format
Texture2D			TextureColor; //color which is output of previous technique (except when drawed to temporary render target), R10B10G10A2 32 bit ldr format
Texture2D			TextureDepth; //scene depth R32F 32 bit hdr format

//temporary textures which can be set as render target for techniques via annotations like <string RenderTarget="RenderTargetRGBA32";>
Texture2D			RenderTargetRGBA32; //R8G8B8A8 32 bit ldr format
Texture2D			RenderTargetRGBA64; //R16B16G16A16 64 bit ldr format
Texture2D			RenderTargetRGBA64F; //R16B16G16A16F 64 bit hdr format
Texture2D			RenderTargetR16F; //R16F 16 bit hdr format with red channel only
Texture2D			RenderTargetR32F; //R32F 32 bit hdr format with red channel only
Texture2D			RenderTargetRGB32F; //32 bit hdr format without alpha

SamplerState		Sampler0
{
	Filter = MIN_MAG_MIP_POINT;//MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};
SamplerState		Sampler1
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};



//+++++++++++++++++++++++++++++
//
//+++++++++++++++++++++++++++++
struct VS_INPUT_POST
{
	float3 pos		: POSITION;
	float2 txcoord	: TEXCOORD0;
};
struct VS_OUTPUT_POST
{
	float4 pos		: SV_POSITION;
	float2 txcoord0	: TEXCOORD0;
};



//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VS_OUTPUT_POST	VS_PostProcess(VS_INPUT_POST IN)
{
	VS_OUTPUT_POST	OUT;
	float4	pos;
	pos.xyz=IN.pos.xyz;
	pos.w=1.0;
	OUT.pos=pos;
	OUT.txcoord0.xy=IN.txcoord.xy;
	return OUT;
}



float Min3(float x, float y, float z)
{
    return min(x, min(y, z));
}

float Max3(float x, float y, float z)
{
    return max(x, max(y, z));
}

float4	PS_Sharpening(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float4	color;
	float4	centercolor;
	float2	pixeloffset=ScreenSize.y;
	pixeloffset.y*=ScreenSize.z;

	color=TextureColor.Sample(Sampler0, IN.txcoord0.xy);

	// fetch a 3x3 neighborhood around the pixel 'e',
    //  a b c
    //  d(e)f
    //  g h i
    float pixelX = pixeloffset.x;
    float pixelY = pixeloffset.y;
    
    float3 a = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(-pixelX, -pixelY)).rgb;
    float3 b = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(0.0, -pixelY)).rgb;
    float3 c = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(pixelX, -pixelY)).rgb;
    float3 d = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(-pixelX, 0.0)).rgb;
    float3 e = TextureColor.Sample(Sampler1, IN.txcoord0.xy).rgb;
    float3 f = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(pixelX, 0.0)).rgb;
    float3 g = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(-pixelX, pixelY)).rgb;
    float3 h = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(0.0, pixelY)).rgb;
    float3 i = TextureColor.Sample(Sampler1, IN.txcoord0.xy + float2(pixelX, pixelY)).rgb;

	// Soft min and max.
	//  a b c             b
	//  d e f * 0.5  +  d e f * 0.5
	//  g h i             h
    // These are 2.0x bigger (factored out the extra multiply).
    float mnR = Min3( Min3(d.r, e.r, f.r), b.r, h.r);
    float mnG = Min3( Min3(d.g, e.g, f.g), b.g, h.g);
    float mnB = Min3( Min3(d.b, e.b, f.b), b.b, h.b);
    
    float mnR2 = Min3( Min3(mnR, a.r, c.r), g.r, i.r);
    float mnG2 = Min3( Min3(mnG, a.g, c.g), g.g, i.g);
    float mnB2 = Min3( Min3(mnB, a.b, c.b), g.b, i.b);
    mnR = mnR + mnR2;
    mnG = mnG + mnG2;
    mnB = mnB + mnB2;
    
    float mxR = Max3( Max3(d.r, e.r, f.r), b.r, h.r);
    float mxG = Max3( Max3(d.g, e.g, f.g), b.g, h.g);
    float mxB = Max3( Max3(d.b, e.b, f.b), b.b, h.b);
    
    float mxR2 = Max3( Max3(mxR, a.r, c.r), g.r, i.r);
    float mxG2 = Max3( Max3(mxG, a.g, c.g), g.g, i.g);
    float mxB2 = Max3( Max3(mxB, a.b, c.b), g.b, i.b);
    mxR = mxR + mxR2;
    mxG = mxG + mxG2;
    mxB = mxB + mxB2;
    
    // Smooth minimum distance to signal limit divided by smooth max.
    float rcpMR = rcp(mxR);
    float rcpMG = rcp(mxG);
    float rcpMB = rcp(mxB);

    float ampR = saturate(min(mnR, 2.0 - mxR) * rcpMR);
    float ampG = saturate(min(mnG, 2.0 - mxG) * rcpMG);
    float ampB = saturate(min(mnB, 2.0 - mxB) * rcpMB);
    
    // Shaping amount of sharpening.
    ampR = sqrt(ampR);
    ampG = sqrt(ampG);
    ampB = sqrt(ampB);
    
   // Filter shape.
   //  0 w 0
   //  w 1 w
   //  0 w 0  
   float peak = -rcp(lerp(8.0, 5.0, saturate(ESharpAmount)));
   
   float wR = ampR * peak;
   float wG = ampG * peak;
   float wB = ampB * peak;
   
   float rcpWeightR = rcp(1.0 + 4.0 * wR);
   float rcpWeightG = rcp(1.0 + 4.0 * wG);
   float rcpWeightB = rcp(1.0 + 4.0 * wB);
   
   float3 outColor = float3(saturate((b.r*wR+d.r*wR+f.r*wR+h.r*wR+e.r)*rcpWeightR),
                            saturate((b.g*wG+d.g*wG+f.g*wG+h.g*wG+e.g)*rcpWeightG),
                            saturate((b.b*wB+d.b*wB+f.b*wB+h.b*wB+e.b)*rcpWeightB));

	return float4(outColor,1.0);
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Techniques are drawn one after another and they use the result of
// the previous technique as input color to the next one.  The number
// of techniques is limited to 255.  If UIName is specified, then it
// is a base technique which may have extra techniques with indexing
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//sharpening example

//blur example applied twice
technique11 CAS <string UIName="CAS";>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_PostProcess()));
		SetPixelShader(CompileShader(ps_5_0, PS_Sharpening()));
	}
}

#define  SMAA_UINAME 0 
#define  PASSNAME0   CAS1
#define  PASSNAME1   CAS2
#define  PASSNAME2   CAS3
#include "enbsmaa.fx" 
