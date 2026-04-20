// 图片压缩结果
export interface CompressResult {
  compressed_size: number;
  original_size: number;
  saved_bytes: number;
  ratio: number;
  output_path: string;
}

// 视频信息
export interface VideoInfo {
  duration: number;
  width: number;
  height: number;
  fps: number;
  file_size: number;
}

// GIF转换结果
export interface GifResult {
  output_path: string;
  file_size: number;
}

// 压缩日志条目
export interface CompressionLog {
  id: string;
  timestamp: Date;
  filename: string;
  original_size: number;
  compressed_size: number;
  status: 'waiting' | 'compressing' | 'success' | 'failed';
  message?: string;
  extension: string;
}

// 压缩设置
export interface CompressSettings {
  engine: 'tinypng' | 'local';
  quality: 'ultraLow' | 'low' | 'medium' | 'high';
  overwrite: boolean;
  scaleLongSide?: number;
}

// 视频转GIF设置
export interface GifSettings {
  quality: number;
  width: number;
  fps: number;
}

// TinyPNG统计
export interface TinyPNGStats {
  compressed_count: number;
  saved_bytes: number;
  average_ratio: number;
  monthly_remaining: number;
}

// 应用设置
export interface AppSettings {
  tinypng_api_key: string;
}
