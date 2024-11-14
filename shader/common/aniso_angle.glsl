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

float getAnisotropyAngleSample(sampler2D map, vec2 uv, bool disableFragment, float defaultValue)
{
	const float PI = 3.1415927;

	if (disableFragment)
		return defaultValue;

	ivec2 texSize = ivec2(textureSize(map, 0));
	ivec2 itex_coord = ivec2(uv * vec2(texSize));
	// Assuming tex sizes are pow of 2, we can do the fast modulo
	ivec2 texSizeMask = texSize - ivec2(1);

	// Fetch the 4 samples needed
	float a00 = 2.0 * PI * texelFetch(map,  itex_coord                & texSizeMask, 0).x;
	float a01 = 2.0 * PI * texelFetch(map, (itex_coord + ivec2(1, 0)) & texSizeMask, 0).x - a00;
	float a10 = 2.0 * PI * texelFetch(map, (itex_coord + ivec2(0, 1)) & texSizeMask, 0).x - a00;
	float a11 = 2.0 * PI * texelFetch(map, (itex_coord + ivec2(1, 1)) & texSizeMask, 0).x - a00;

	// Detect if the angle warps inside the filtering footprint, and fix it
	a01 += abs(a01) > PI ? -2.0 * PI * sign(a01) + a00 : a00;
	a10 += abs(a10) > PI ? -2.0 * PI * sign(a10) + a00 : a00;
	a11 += abs(a11) > PI ? -2.0 * PI * sign(a11) + a00 : a00;

	// Bilinear blending of the samples
	vec2 t = uv * vec2(texSize) - vec2(itex_coord);
	return mix(mix(a00, a01, t.x), mix(a10, a11, t.x), t.y);
}