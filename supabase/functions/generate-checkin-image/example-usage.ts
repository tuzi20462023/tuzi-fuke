/**
 * generate-checkin-image Edge Function 使用示例
 *
 * 这个文件展示了如何在客户端调用 Edge Function
 */

import { createClient } from '@supabase/supabase-js';

// 初始化 Supabase 客户端
const supabaseUrl = 'https://your-project-ref.supabase.co';
const supabaseAnonKey = 'your-anon-key';
const supabase = createClient(supabaseUrl, supabaseAnonKey);

/**
 * 示例 1: 生成 Selfie 风格图片（纯文本）
 */
async function generateSelfieImage() {
  console.log('生成 Selfie 风格图片...');

  const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
    body: {
      prompt: '在星巴克喝咖啡，阳光明媚，心情愉快',
      mode: 'selfie',
      userId: 'user-123'
    }
  });

  if (error) {
    console.error('生成失败:', error);
    return;
  }

  console.log('生成成功!');
  console.log('图片URL:', data.image_url);
  return data.image_url;
}

/**
 * 示例 2: 生成 Cartoon 风格图片（纯文本）
 */
async function generateCartoonImage() {
  console.log('生成 Cartoon 风格图片...');

  const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
    body: {
      prompt: '在公园里野餐，有可爱的小动物',
      mode: 'cartoon'
    }
  });

  if (error) {
    console.error('生成失败:', error);
    return;
  }

  console.log('生成成功!');
  console.log('图片URL:', data.image_url);
  return data.image_url;
}

/**
 * 示例 3: 生成 Landscape 风格图片
 */
async function generateLandscapeImage() {
  console.log('生成 Landscape 风格图片...');

  const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
    body: {
      prompt: '美丽的海滩日落，波浪轻柔',
      mode: 'landscape',
      userId: 'user-123'
    }
  });

  if (error) {
    console.error('生成失败:', error);
    return;
  }

  console.log('生成成功!');
  console.log('图片URL:', data.image_url);
  return data.image_url;
}

/**
 * 示例 4: 带头像生成图片
 */
async function generateImageWithAvatar(avatarFile: File) {
  console.log('生成带头像的图片...');

  // 将文件转换为 base64
  const avatarBase64 = await fileToBase64(avatarFile);

  const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
    body: {
      prompt: '在咖啡店工作，面带微笑',
      mode: 'selfie',
      avatarBase64: avatarBase64,
      userId: 'user-123'
    }
  });

  if (error) {
    console.error('生成失败:', error);
    return;
  }

  console.log('生成成功!');
  console.log('图片URL:', data.image_url);
  return data.image_url;
}

/**
 * 辅助函数：将文件转换为 base64
 */
function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.readAsDataURL(file);
    reader.onload = () => {
      const base64String = reader.result as string;
      // 移除 data:image/xxx;base64, 前缀（可选，Edge Function 会自动处理）
      const base64 = base64String.split(',')[1];
      resolve(base64);
    };
    reader.onerror = error => reject(error);
  });
}

/**
 * React 组件示例
 */
export function CheckinImageGenerator() {
  const [loading, setLoading] = React.useState(false);
  const [imageUrl, setImageUrl] = React.useState<string | null>(null);
  const [prompt, setPrompt] = React.useState('');
  const [mode, setMode] = React.useState<'selfie' | 'cartoon' | 'landscape'>('selfie');

  const handleGenerate = async () => {
    if (!prompt.trim()) {
      alert('请输入图片描述');
      return;
    }

    setLoading(true);
    setImageUrl(null);

    try {
      const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
        body: {
          prompt: prompt,
          mode: mode,
          userId: 'current-user-id' // 从认证状态获取
        }
      });

      if (error) throw error;

      setImageUrl(data.image_url);
      console.log('图片生成成功:', data.image_url);
    } catch (error) {
      console.error('生成失败:', error);
      alert('生成失败，请重试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="checkin-image-generator">
      <h2>AI 打卡图片生成器</h2>

      <div className="form-group">
        <label>描述你的打卡场景：</label>
        <textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder="例如：在星巴克喝咖啡，阳光明媚"
          rows={3}
        />
      </div>

      <div className="form-group">
        <label>选择风格：</label>
        <select value={mode} onChange={(e) => setMode(e.target.value as any)}>
          <option value="selfie">自拍风格</option>
          <option value="cartoon">卡通风格</option>
          <option value="landscape">风景风格</option>
        </select>
      </div>

      <button onClick={handleGenerate} disabled={loading}>
        {loading ? '生成中...' : '生成图片'}
      </button>

      {imageUrl && (
        <div className="result">
          <h3>生成结果：</h3>
          <img src={imageUrl} alt="Generated checkin" />
          <a href={imageUrl} target="_blank" rel="noopener noreferrer">
            查看原图
          </a>
        </div>
      )}
    </div>
  );
}

/**
 * Vue 组件示例
 */
export const CheckinImageGeneratorVue = {
  data() {
    return {
      loading: false,
      imageUrl: null,
      prompt: '',
      mode: 'selfie'
    };
  },
  methods: {
    async handleGenerate() {
      if (!this.prompt.trim()) {
        alert('请输入图片描述');
        return;
      }

      this.loading = true;
      this.imageUrl = null;

      try {
        const { data, error } = await supabase.functions.invoke('generate-checkin-image', {
          body: {
            prompt: this.prompt,
            mode: this.mode,
            userId: 'current-user-id'
          }
        });

        if (error) throw error;

        this.imageUrl = data.image_url;
        console.log('图片生成成功:', data.image_url);
      } catch (error) {
        console.error('生成失败:', error);
        alert('生成失败，请重试');
      } finally {
        this.loading = false;
      }
    }
  },
  template: `
    <div class="checkin-image-generator">
      <h2>AI 打卡图片生成器</h2>

      <div class="form-group">
        <label>描述你的打卡场景：</label>
        <textarea
          v-model="prompt"
          placeholder="例如：在星巴克喝咖啡，阳光明媚"
          rows="3"
        ></textarea>
      </div>

      <div class="form-group">
        <label>选择风格：</label>
        <select v-model="mode">
          <option value="selfie">自拍风格</option>
          <option value="cartoon">卡通风格</option>
          <option value="landscape">风景风格</option>
        </select>
      </div>

      <button @click="handleGenerate" :disabled="loading">
        {{ loading ? '生成中...' : '生成图片' }}
      </button>

      <div v-if="imageUrl" class="result">
        <h3>生成结果：</h3>
        <img :src="imageUrl" alt="Generated checkin" />
        <a :href="imageUrl" target="_blank" rel="noopener noreferrer">
          查看原图
        </a>
      </div>
    </div>
  `
};

// 如果你想直接运行测试
if (import.meta.main) {
  console.log('运行测试示例...');
  await generateSelfieImage();
  await new Promise(resolve => setTimeout(resolve, 2000));
  await generateCartoonImage();
  await new Promise(resolve => setTimeout(resolve, 2000));
  await generateLandscapeImage();
}
