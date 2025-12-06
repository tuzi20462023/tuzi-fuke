import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { GoogleGenAI } from "npm:@google/genai";

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

interface GenerateCheckinImageRequest {
  latitude: number;
  longitude: number;
  avatarBase64?: string;
  userId?: string;
}

interface GenerateCheckinImageResponse {
  success: boolean;
  image_url?: string;
  error?: string;
}

Deno.serve(async (req) => {
  try {
    console.log('🎨 [打卡图片生成] Edge Function启动');

    // 1. 解析请求
    const { latitude, longitude, avatarBase64, userId }: GenerateCheckinImageRequest = await req.json();

    if (latitude === undefined || longitude === undefined) {
      return new Response(
        JSON.stringify({ success: false, error: '缺少经纬度参数' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`📍 [位置] ${latitude}, ${longitude}`);
    console.log(`👤 [头像] ${avatarBase64 ? '已提供' : '未提供'}`);

    // 2. 初始化Supabase客户端
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 3. 构建提示词
    const prompt = buildPrompt(latitude, longitude, !!avatarBase64);
    console.log(`📝 [提示词] ${prompt}`);

    // 4. 调用Gemini API生成图片
    console.log('🤖 [Gemini API] 开始生成图片...');
    const imageData = await generateImageWithGemini(prompt, avatarBase64);

    if (!imageData) {
      return new Response(
        JSON.stringify({ success: false, error: 'Gemini API生成图片失败' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`✅ [Gemini API] 图片生成成功，大小: ${imageData.byteLength} bytes`);

    // 5. 上传到Supabase Storage
    const timestamp = Date.now();
    const randomId = Math.random().toString(36).substring(2, 15);
    const fileName = `postcard_${timestamp}_${randomId}.png`;
    const filePath = userId ? `${userId}/${fileName}` : `public/${fileName}`;

    console.log(`📤 [上传] 上传路径: ${filePath}`);

    const { error: uploadError } = await supabase.storage
      .from('checkin-photos')
      .upload(filePath, imageData, {
        contentType: 'image/png',
        upsert: false
      });

    if (uploadError) {
      console.error('❌ 上传图片失败:', uploadError);
      return new Response(
        JSON.stringify({ success: false, error: `上传图片失败: ${uploadError.message}` }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`✅ [上传] 图片已上传: ${filePath}`);

    // 6. 获取公开URL
    const { data: imageUrl } = supabase.storage
      .from('checkin-photos')
      .getPublicUrl(filePath);

    // 7. 返回结果
    const response: GenerateCheckinImageResponse = {
      success: true,
      image_url: imageUrl.publicUrl
    };

    console.log('✨ [完成] 图片生成成功！');
    console.log(`🔗 [URL] ${imageUrl.publicUrl}`);

    return new Response(
      JSON.stringify(response),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('❌ [错误]', error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      }
    );
  }
});

/**
 * 构建明信片风格提示词
 */
function buildPrompt(latitude: number, longitude: number, hasAvatar: boolean): string {
  const baseStyle = `
⚠️⚠️⚠️ CRITICAL: THIS MUST BE A CARTOON/ANIME ILLUSTRATION - ABSOLUTELY NO REALISTIC PHOTOS! ⚠️⚠️⚠️

🎨 ART STYLE (STRICTLY FOLLOW):
- 2D hand-drawn anime/cartoon illustration style
- Like Studio Ghibli (宫崎骏), Makoto Shinkai (新海诚), or Disney/Pixar concept art
- Cell-shaded coloring with flat colors and clean outlines
- Stylized, NOT photorealistic
- Looks like digital painting or watercolor illustration
- Similar to: "Your Name" anime, "Spirited Away", children's book illustrations

STEP 1 - LOCATION RESEARCH:
Use Google Search to find what is at coordinates ${latitude}, ${longitude}.
- Find the actual place: streets, buildings, lakes, parks, shops
- Note the real environment, then REDRAW it in cute cartoon style

STEP 2 - CARTOON RENDERING (MANDATORY):
Transform the real location into anime/cartoon art:
- Simplify complex details into clean cartoon shapes
- Use bright, saturated anime color palette
- Add dreamy atmosphere: soft glow, light rays, sparkles
- Make buildings look cute and charming (rounded edges, warm colors)
- Beautiful illustrated sky with fluffy stylized clouds
- Add whimsical details: birds, butterflies, cherry blossoms, floating particles

STEP 3 - POSTCARD TEXT:
- Add "Greetings from 惠州" in cute decorative cartoon font
- Use ONLY city name, not street names
- Cute banner or ribbon style`;

  if (hasAvatar) {
    return `⚠️ GENERATE A 2D ANIME/CARTOON ILLUSTRATION - NOT A PHOTO! ⚠️

Create a cute anime-style postcard illustration at coordinates: ${latitude}, ${longitude}

${baseStyle}

🧑‍🎨 CONVERT PERSON TO CARTOON CHARACTER (VERY IMPORTANT):
- Transform the reference photo person into a 2D ANIME CHARACTER
- Use the SAME cartoon art style as the background
- Anime features: large expressive eyes, simplified nose, small mouth
- Keep their hair color, hairstyle, clothing but in cartoon/anime form
- Cute happy expression, kawaii style
- The person must look DRAWN/ILLUSTRATED, not like a real photo
- Think: how would Studio Ghibli draw this person?

🎯 FINAL OUTPUT: A cohesive 2D anime-style illustrated postcard where BOTH the background AND the person are in matching cartoon style. NO photorealistic elements.`;
  } else {
    return `⚠️ GENERATE A 2D ANIME/CARTOON ILLUSTRATION - NOT A PHOTO! ⚠️

Create a cute anime-style postcard illustration at coordinates: ${latitude}, ${longitude}

${baseStyle}

COMPOSITION:
- Beautiful 2D illustrated landscape
- Anime/cartoon art style throughout
- Like a background painting from a Ghibli film

🎯 FINAL OUTPUT: A beautiful 2D anime-style illustrated postcard. NO photorealistic elements.`;
  }
}

/**
 * 使用官方 @google/genai SDK 调用 Gemini API 生成图片
 */
async function generateImageWithGemini(
  prompt: string,
  avatarBase64?: string
): Promise<Uint8Array | null> {
  try {
    console.log('📤 [Gemini API] 使用官方SDK发送请求...');

    // 初始化 Gemini AI 客户端
    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

    // 构建请求内容
    let contents: any;

    if (avatarBase64) {
      // 有头像时，发送图片+文字
      const cleanBase64 = avatarBase64.replace(/^data:image\/\w+;base64,/, '');
      const fullPrompt = prompt + '\n\n🚨🚨🚨 ABSOLUTE REQUIREMENT 🚨🚨🚨\nThe output image MUST be a 2D CARTOON/ANIME STYLE ILLUSTRATION.\nDO NOT generate a realistic photograph.\nDO NOT keep the person looking like a real photo.\nCONVERT the person into an ANIME CHARACTER with the same art style as the background.\nThe final image should look like it was HAND-DRAWN by an animator, not photographed by a camera.\nStyle reference: Studio Ghibli, Makoto Shinkai anime films, Disney concept art.';

      contents = [
        { text: fullPrompt },
        {
          inlineData: {
            mimeType: 'image/jpeg',
            data: cleanBase64
          }
        }
      ];
    } else {
      // 无头像时，只发送文字
      contents = prompt;
    }

    console.log('   模型: gemini-2.0-flash-exp');
    console.log('   内容类型:', avatarBase64 ? '文字+图片' : '纯文字');

    // 调用 Gemini API
    const response = await ai.models.generateContent({
      model: 'gemini-2.0-flash-exp',
      contents: contents,
      config: {
        responseModalities: ['TEXT', 'IMAGE'],
      },
    });

    console.log('📥 [Gemini API] 收到响应');

    // 提取图片数据
    if (!response.candidates || response.candidates.length === 0) {
      console.error('❌ [Gemini API] 没有返回候选结果');
      return null;
    }

    const parts = response.candidates[0].content?.parts;
    if (!parts || parts.length === 0) {
      console.error('❌ [Gemini API] 没有返回内容部分');
      return null;
    }

    // 查找图片数据
    let imageBase64: string | null = null;
    for (const part of parts) {
      if (part.inlineData && part.inlineData.data) {
        imageBase64 = part.inlineData.data;
        console.log('✅ [Gemini API] 找到图片数据，长度:', imageBase64.length);
        break;
      }
    }

    if (!imageBase64) {
      console.error('❌ [Gemini API] 未找到图片数据');
      console.error('   Parts:', JSON.stringify(parts, null, 2));
      return null;
    }

    // 解码 base64
    const binaryString = atob(imageBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    console.log('✅ [图片解码] 成功，字节大小:', bytes.byteLength);

    return bytes;

  } catch (error) {
    console.error('❌ [Gemini API] 调用失败:', error);
    console.error('   错误详情:', error.message);
    return null;
  }
}
