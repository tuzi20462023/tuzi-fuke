import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { GoogleGenAI } from "npm:@google/genai";

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

Deno.serve(async (req) => {
  try {
    console.log('Edge Function启动');

    const { latitude, longitude, avatarBase64, userId } = await req.json();

    if (latitude === undefined || longitude === undefined) {
      return new Response(
        JSON.stringify({ success: false, error: '缺少经纬度参数' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log('位置:', latitude, longitude);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const prompt = buildPrompt(latitude, longitude, !!avatarBase64);

    console.log('开始生成图片...');
    const imageData = await generateImageWithGemini(prompt, avatarBase64);

    if (!imageData) {
      return new Response(
        JSON.stringify({ success: false, error: 'Gemini API生成图片失败' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log('图片生成成功，大小:', imageData.byteLength);

    const timestamp = Date.now();
    const randomId = Math.random().toString(36).substring(2, 15);
    const fileName = 'postcard_' + timestamp + '_' + randomId + '.png';
    const filePath = userId ? userId + '/' + fileName : 'public/' + fileName;

    const { error: uploadError } = await supabase.storage
      .from('checkin-photos')
      .upload(filePath, imageData, {
        contentType: 'image/png',
        upsert: false
      });

    if (uploadError) {
      console.error('上传图片失败:', uploadError);
      return new Response(
        JSON.stringify({ success: false, error: '上传图片失败: ' + uploadError.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const { data: imageUrl } = supabase.storage
      .from('checkin-photos')
      .getPublicUrl(filePath);

    console.log('完成！URL:', imageUrl.publicUrl);

    return new Response(
      JSON.stringify({ success: true, image_url: imageUrl.publicUrl }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('错误:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});

function buildPrompt(latitude: number, longitude: number, hasAvatar: boolean): string {
  const basePrompt = 'Generate a beautiful postcard-style travel photo at coordinates: ' + latitude + ', ' + longitude + '. Create a stunning photograph with beautiful lighting, warm travel photography feel, high quality Instagram-worthy aesthetic.';

  if (hasAvatar) {
    return basePrompt + ' Include the person from the provided photo naturally in the scene.';
  }
  return basePrompt;
}

async function generateImageWithGemini(prompt: string, avatarBase64?: string): Promise<Uint8Array | null> {
  try {
    console.log('使用官方SDK发送请求...');

    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

    let contents: any;

    if (avatarBase64) {
      const cleanBase64 = avatarBase64.replace(/^data:image\/\w+;base64,/, '');
      contents = [
        { text: prompt },
        { inlineData: { mimeType: 'image/jpeg', data: cleanBase64 } }
      ];
    } else {
      contents = prompt;
    }

    console.log('模型: gemini-2.0-flash-exp');

    const response = await ai.models.generateContent({
      model: 'gemini-2.0-flash-exp',
      contents: contents,
      config: {
        responseModalities: ['TEXT', 'IMAGE'],
      },
    });

    console.log('收到响应');

    if (!response.candidates || response.candidates.length === 0) {
      console.error('没有返回候选结果');
      return null;
    }

    const parts = response.candidates[0].content?.parts;
    if (!parts || parts.length === 0) {
      console.error('没有返回内容部分');
      return null;
    }

    let imageBase64: string | null = null;
    for (const part of parts) {
      if (part.inlineData && part.inlineData.data) {
        imageBase64 = part.inlineData.data;
        console.log('找到图片数据');
        break;
      }
    }

    if (!imageBase64) {
      console.error('未找到图片数据');
      return null;
    }

    const binaryString = atob(imageBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    return bytes;

  } catch (error) {
    console.error('Gemini API调用失败:', error);
    return null;
  }
}
