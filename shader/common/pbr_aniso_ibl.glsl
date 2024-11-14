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

#include "pbr_ibl.glsl"

float normal_distrib(
	vec3 localH,
	vec2 alpha)
{
	localH.xy /= alpha;
	float tmp = dot(localH, localH);
	return 1.0 / (M_PI * alpha.x * alpha.y * tmp * tmp);
}

float G1(
	vec3 localW, // W is either localL or localV
	vec2 alpha)
{
	// One generic factor of the geometry function divided by ndw
	localW.xy *= alpha;
	return 2.0 / max(1e-8, localW.z + length(localW));
}

float visibility(
	vec3 localL,
	vec3 localV,
	vec2 alpha)
{
	// visibility is a Cook-Torrance geometry function divided by (n.l)*(n.v)
	return G1(localL, alpha) * G1(localV, alpha);
}

vec3 microfacets_brdf(
	vec3 localL,
	vec3 localV,
	vec3 Ks,
	vec2 alpha)
{
	vec3 localH = normalize(localL + localV);
	float vdh = max(0.0, dot(localV, localH));
	return fresnel(vdh, Ks) * (0.25 * normal_distrib(localH, alpha) * visibility(localL, localV, alpha));
}

vec3 microfacets_contrib(
	float vdh,
	float ndh,
	vec3 localL,
	vec3 localV,
	vec3 Ks,
	vec2 alpha)
{
	// This is the contribution when using importance sampling with the GGX based
	// sample distribution. This means ct_contrib = ct_brdf / ggx_probability
	return fresnel(vdh, Ks) * (visibility(localL, localV, alpha) * vdh * localL.z / ndh);
}

vec3 importanceSampleGGX(vec2 Xi, vec2 alpha)
{
	float phi = 2.0 * M_PI * Xi.x;
	vec2 slope = sqrt(Xi.y / (1.0 - Xi.y)) * alpha * vec2(cos(phi), sin(phi));
	return normalize(vec3(slope, 1.0));
}

float probabilityGGX(vec3 localH, float vdh, vec2 alpha)
{
	return normal_distrib(localH, alpha) * localH.z / (4.0 * vdh);
}

void computeSamplingFrame(
	in vec3 iFS_Tangent,
	in vec3 iFS_Binormal,
	in vec3 fixedNormalWS,
	in float anisoAngle,
	out vec3 Tp,
	out vec3 Bp)
{
	vec3 tangent, binormal;
	computeSamplingFrame(iFS_Tangent, iFS_Binormal, fixedNormalWS, tangent, binormal);

	float cosAngle = cos(anisoAngle);
	float sinAngle = sin(anisoAngle);
	Tp = cosAngle * tangent - sinAngle * binormal;
	Bp = cosAngle * binormal + sinAngle * tangent;
}

vec3 pointLightContribution(
	vec3 fixedNormalWS,
	vec3 iFS_Tangent,
	vec3 iFS_Binormal,
	float anisoAngle,
	vec3 pointToLightDirWS,
	vec3 pointToCameraDirWS,
	vec3 diffColor,
	vec3 specColor,
	vec2 roughness,
	vec3 LampColor,
	float LampIntensity,
	float LampDist)
{
	// Note that the lamp intensity is using ˝computer games units" i.e. it needs
	// to be multiplied by M_PI.
	// Cf https://seblagarde.wordpress.com/2012/01/08/pi-or-not-to-pi-in-game-lighting-equation/

	vec3 Tp, Bp;
	computeSamplingFrame(iFS_Tangent, iFS_Binormal, fixedNormalWS, anisoAngle, Tp, Bp);
	mat3 TBN = mat3(Tp, Bp, fixedNormalWS);
	vec3 localL = pointToLightDirWS * TBN;
	vec3 localV = pointToCameraDirWS * TBN;

	return  max(dot(fixedNormalWS,pointToLightDirWS), 0.0) * ( (
		diffuse_brdf(
			fixedNormalWS,
			pointToLightDirWS,
			pointToCameraDirWS,
			diffColor*(vec3(1.0)-specColor))
		+ microfacets_brdf(
			localL,
			localV,
			specColor,
			roughness*roughness) ) *LampColor*(lampAttenuation(LampDist)*LampIntensity*M_PI) );
}

#define ExpandIBLSpecularAnisoContribution(envSamplerType, envLodComputationFunc, envSampleFunc) \
	vec3 IBLSpecularContribution( \
		envSamplerType environmentMap, \
		float envRotation, \
		float maxLod, \
		int nbSamples, \
		vec3 normalWS, \
		vec3 fixedNormalWS, \
		vec3 Tp, \
		vec3 Bp, \
		vec3 pointToCameraDirWS, \
		vec3 specColor, \
		vec2 roughness, \
		float noise) \
{ \
	vec3 radiance = vec3(0.0); \
	vec2 alpha = roughness * roughness; \
	mat3 TBN = mat3(Tp, Bp, fixedNormalWS); \
	vec3 localV = pointToCameraDirWS * TBN; \
	\
	for(int i=0; i<nbSamples; ++i) \
	{ \
		vec2 Xi = fibonacci2D(i, nbSamples); \
		Xi.x += noise; \
		vec3 localH = importanceSampleGGX(Xi, alpha); \
		vec3 localL = reflect(-localV, localH); \
		\
		if (localL.z > 0.0) \
		{ \
			vec3 Ln = TBN * localL; \
			float vdh = max(1e-8, dot(localV, localH)); \
			\
			float horiz = horizonFading(dot(normalWS, Ln)); \
			float pdf = probabilityGGX(localH, vdh, alpha); \
			float lodS = max(roughness.x, roughness.y) < 0.01 ? 0.0 : \
				envLodComputationFunc(Ln, pdf, nbSamples, maxLod); \
			if (roughness.x != roughness.y) lodS -= 1.0; /* Offset lodS to trade bias for more noise */ \
			vec3 preconvolvedSample = envSampleFunc(environmentMap, rotate(Ln,envRotation), lodS); \
			\
			radiance += \
				horiz * preconvolvedSample * \
				microfacets_contrib(vdh, localH.z, localL, localV, specColor, alpha); \
		} \
	} \
	\
	return radiance / float(nbSamples); \
}

ExpandIBLSpecularAnisoContribution(sampler2D  , computeLOD       , samplePanoramicLOD)
ExpandIBLSpecularAnisoContribution(samplerCube, computeCubemapLOD, sampleCubemapLOD  )

#define ExpandComputeIBLAniso(envSamplerType) \
	vec3 computeIBL( \
		envSamplerType environmentMap, \
		float envRotation, \
		float maxLod, \
		int nbSamples, \
		vec3 normalWS, \
		vec3 fixedNormalWS, \
		vec3 iFS_Tangent, \
		vec3 iFS_Binormal, \
		float anisoAngle, \
		vec3 pointToCameraDirWS, \
		vec3 diffColor, \
		vec3 specColor, \
		vec2 roughness, \
		float ambientOcclusion, \
		float noise) \
	{ \
		vec3 Tp,Bp; \
		computeSamplingFrame(iFS_Tangent, iFS_Binormal, fixedNormalWS, anisoAngle, Tp, Bp); \
		\
		vec3 result = IBLSpecularContribution( \
			environmentMap, \
			envRotation, \
			maxLod, \
			nbSamples, \
			normalWS, \
			fixedNormalWS, \
			Tp, \
			Bp, \
			pointToCameraDirWS, \
			specColor, \
			roughness, \
			noise); \
		\
		result += diffColor * (vec3(1.0) - specColor) * \
			irradianceFromSH(rotate(fixedNormalWS,envRotation)); \
		\
		return result * ambientOcclusion; \
	}

ExpandComputeIBLAniso(sampler2D  )
ExpandComputeIBLAniso(samplerCube)