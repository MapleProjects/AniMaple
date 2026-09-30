// Qualcomm Snapdragon Game Super Resolution (GSR) v1 - 2K Upscaler (2560x1440)
// Native Port for AniMaple & MPV libplacebo
// Official single-pass spatial reconstruction upscaled to 1440p (2560x1440)

//!HOOK MAIN
//!BIND HOOKED
//!DESC Qualcomm Snapdragon Game Super Resolution 2K (SGSR 1440p)
//!WIDTH 2560
//!HEIGHT 1440

#define UseEdgeDirection 1
#define EdgeThreshold 4.0
#define EdgeSharpness 2.0

float fastLanczos2(float x)
{
	if (x >= 4.0 || x < 0.0) return 0.0;
	float wA = x - 4.0;
	float wB = x * wA - wA;
	wA *= wA;
	return wB * wA;
}

#if (UseEdgeDirection == 1)
vec2 weightY(float dx, float dy, float c, vec3 data)
{
	float std = data.x;
	vec2 dir = data.yz;

	float edgeDis = ((dx * dir.y) + (dy * dir.x));
	float x = fma(edgeDis * edgeDis, (clamp(c * c * std, 0.0, 1.0) * 0.7 - 1.0), (dx * dx + dy * dy));
	float w = fastLanczos2(x);
	return vec2(w, w * c);
}
#else
vec2 weightY(float dx, float dy, float c, float data)
{
	float std = data;
	float x = fma((dx * dx + dy * dy), 0.55, clamp(abs(c) * std, 0.0, 1.0));
	float w = fastLanczos2(x);
	return vec2(w, w * c);
}
#endif

vec2 edgeDirection(vec4 left, vec4 right)
{
	vec2 delta;
	delta.x = (right.x - left.z) + (right.w - left.y);
	delta.y = (right.x - left.z) - (right.w - left.y);
	return delta * inversesqrt(dot(delta, delta) + 3.075740e-05);
}

vec4 hook()
{
	vec4 color = HOOKED_tex(HOOKED_pos);

	vec2 imgCoord = ((HOOKED_pos * HOOKED_size) + vec2(-0.5, 0.5));
	vec2 imgCoordPixel = floor(imgCoord);
	vec2 coord = (imgCoordPixel * HOOKED_pt);
	vec2 pl = (imgCoord - imgCoordPixel);

	// Gather green channel (channel 1 = perceptual luma in RGB pipeline)
	vec4 left = HOOKED_gather(coord, 1);

	float edgeVote = abs(left.z - left.y) + abs(color.g - left.y) + abs(color.g - left.z);
	if (edgeVote > (EdgeThreshold / 255.0))
	{
		coord.x += HOOKED_pt.x;

		vec4 right = HOOKED_gather(coord + vec2(HOOKED_pt.x, 0.0), 1);
		vec4 upDown;
		upDown.xy = HOOKED_gather(coord + vec2(0.0, -HOOKED_pt.y), 1).wz;
		upDown.zw = HOOKED_gather(coord + vec2(0.0, HOOKED_pt.y), 1).yx;

		float mean = (left.y + left.z + right.x + right.w) * 0.25;
		left -= vec4(mean);
		right -= vec4(mean);
		upDown -= vec4(mean);
		float colorDiff = color.g - mean;

		float sum = dot(abs(left) + abs(right) + abs(upDown), vec4(1.0));

#if (UseEdgeDirection == 1)
		float sumMean = 1.014185e+01 / max(sum, 0.0001);
		float std = sumMean * sumMean;
		vec3 data = vec3(std, edgeDirection(left, right));
#else
		float std = 2.181818 / max(sum, 0.0001);
		float data = std;
#endif
		vec2 aWY = weightY(pl.x,       pl.y + 1.0, upDown.x, data);
		     aWY += weightY(pl.x - 1.0, pl.y + 1.0, upDown.y, data);
		     aWY += weightY(pl.x - 1.0, pl.y - 2.0, upDown.z, data);
		     aWY += weightY(pl.x,       pl.y - 2.0, upDown.w, data);
		     aWY += weightY(pl.x + 1.0, pl.y - 1.0,   left.x, data);
		     aWY += weightY(pl.x,       pl.y - 1.0,   left.y, data);
		     aWY += weightY(pl.x,       pl.y,         left.z, data);
		     aWY += weightY(pl.x + 1.0, pl.y,         left.w, data);
		     aWY += weightY(pl.x - 1.0, pl.y - 1.0,  right.x, data);
		     aWY += weightY(pl.x - 2.0, pl.y - 1.0,  right.y, data);
		     aWY += weightY(pl.x - 2.0, pl.y,        right.z, data);
		     aWY += weightY(pl.x - 1.0, pl.y,        right.w, data);

		float finalY = aWY.y / max(aWY.x, 0.0001);
		float maxY = max(max(left.y, left.z), max(right.x, right.w));
		float minY = min(min(left.y, left.z), min(right.x, right.w));
		float deltaY = clamp(EdgeSharpness * finalY, minY, maxY) - colorDiff;

		deltaY = clamp(deltaY, -23.0 / 255.0, 23.0 / 255.0);

		color.rgb = clamp(color.rgb + vec3(deltaY), 0.0, 1.0);
	}

	return color;
}
