/*
Copyright (c) 2022, Adobe. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.
   * Neither the name of the Adobe nor the
     names of its contributors may be used to endorse or promote products
     derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL ADOBE BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//////////////////////////////// Evaluation shader
#version 410

#include "../uvtile.glsl"

layout(triangles, equal_spacing, ccw) in;

in vec4 oTCS_Normal[];
in vec2 oTCS_UV[];
in vec4 oTCS_Tangent[];
in vec4 oTCS_Binormal[];

uniform mat4 worldMatrix;
uniform mat4 worldViewProjMatrix;
uniform mat4 worldInverseTransposeMatrix;

uniform sampler2D heightMap;

uniform float tiling = 1.0;
uniform float heightMapScale = 1.0f;
uniform float scalarZeroValue = 0.5f;
uniform bool uvwScaleEnabled = false;
uniform vec3 uvwScale = vec3(1.0f, 1.0f, 1.0f);

uniform bool usePhongTessellation = false;
uniform float phongTessellationFactor = 0.6;

out vec3 iFS_Normal;
out vec2 iFS_UV;
out vec3 iFS_Tangent;
out vec3 iFS_Binormal;
out vec3 iFS_PointWS;

vec3 interpolate3D(vec3 v0, vec3 v1, vec3 v2, vec3 uvw)
{
  return uvw.x * v0 + uvw.y * v1 + uvw.z * v2;
}

vec2 interpolate2D(vec2 v0, vec2 v1, vec2 v2, vec3 uvw)
{
  return uvw.x * v0 + uvw.y * v1 + uvw.z * v2;
}

/** Orthogonal projection
 * Project x onto the plane defined by
 * the point planePos and the normal planeNormal.
 */
vec3 projectOn (vec3 x, vec3 planePos, vec3 planeNormal)
{
  float w = dot (x - planePos, planeNormal);
  return (x - (w * planeNormal));
}

/** Procedural Phong Tessellation displacement.
 * An Hermite projection driven by the point-normal attributes of the primitive,
 * reproducing a quadratic patch without explicitly constructing any spline.
 * Alpha = 0.6 is a good default value.
 * For more details, check
 *  Phong Tessellation
 *  T. Boubekeur & M. Alexa
 *  ACM Transactions on Graphics (Proc. SIGGRAPH Asia)
 *  2008 
 */
vec3 phongTessellationProjection (vec3 p0, vec3 n0, vec3 p1, vec3 n1, vec3 p2, vec3 n2, vec3 omega, float alpha)
{
  vec3 linearInterp = interpolate3D (p0, p1, p2, omega);

  // Hermite interpolation 
  vec3 phongInterp = interpolate3D (projectOn (linearInterp, p0, n0),
                                    projectOn (linearInterp, p1, n1),
                                    projectOn (linearInterp, p2, n2),
                                    omega);

  // Modulation
  return mix (linearInterp, phongInterp, alpha);  
}

void main()
{
  vec3 uvw = gl_TessCoord.xyz;

  vec3 newPos = interpolate3D(gl_in[0].gl_Position.xyz, gl_in[1].gl_Position.xyz, gl_in[2].gl_Position.xyz, uvw);

  if (usePhongTessellation)
    newPos = phongTessellationProjection (gl_in[0].gl_Position.xyz, oTCS_Normal[0].xyz,
                                          gl_in[1].gl_Position.xyz, oTCS_Normal[1].xyz,
                                          gl_in[2].gl_Position.xyz, oTCS_Normal[2].xyz,
                                          uvw,
                                          phongTessellationFactor);

  vec3 newNormal = interpolate3D(oTCS_Normal[0].xyz, oTCS_Normal[1].xyz, oTCS_Normal[2].xyz, uvw);
  vec3 newTangent = interpolate3D(oTCS_Tangent[0].xyz, oTCS_Tangent[1].xyz, oTCS_Tangent[2].xyz, uvw);
  vec3 newBinormal = interpolate3D(oTCS_Binormal[0].xyz, oTCS_Binormal[1].xyz, oTCS_Binormal[2].xyz, uvw);
  vec2 newUV = interpolate2D(oTCS_UV[0], oTCS_UV[1], oTCS_UV[2], uvw);

  bool disableFragment = hasToDisableFragment(newUV);

  vec2 finalUvScale = (uvwScaleEnabled ? uvwScale.xy : vec2(1.)) * tiling;

  float  heightTexSample = get2DSample(heightMap, newUV * finalUvScale, disableFragment, cDefaultColor.mHeight).x - scalarZeroValue;

  float scale = heightMapScale;
  if (!disableFragment)
    newPos += newNormal * heightTexSample * scale / tiling * 1.0;

  vec4 obj_pos = vec4(newPos, 1);
  gl_Position = worldViewProjMatrix * obj_pos;

  iFS_UV = newUV;
  iFS_Tangent = normalize((worldInverseTransposeMatrix*vec4(newTangent,0)).xyz);
  iFS_Binormal = normalize((worldInverseTransposeMatrix*vec4(newBinormal,0)).xyz);
  iFS_Normal = normalize((worldInverseTransposeMatrix*vec4(newNormal,0)).xyz);
  iFS_PointWS = (worldMatrix * obj_pos).xyz;
}
