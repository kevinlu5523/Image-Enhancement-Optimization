function avgIntensity = calculate_brightness(img)
    % 檢查是否為 RGB 格式
    if size(img, 3) ~= 3
        error('輸入影像 %s 不是 RGB 格式！');
    end
    
    % 轉換為灰階並計算平均亮度
    gray_img = rgb2gray(img); % 將 RGB 轉為灰階（0 到 255）
    avgIntensity = mean(gray_img(:), 'omitnan'); % 計算平均亮度
end