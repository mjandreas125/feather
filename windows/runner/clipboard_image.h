#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_

#include <cstdint>
#include <string>
#include <vector>

// PNG bytes of the image on the clipboard (screenshots, copied pictures); empty if none.
std::vector<uint8_t> ClipboardImagePng();

// Paths of files copied in Explorer (CF_HDROP), UTF-8.
std::vector<std::string> ClipboardFiles();

#endif  // RUNNER_CLIPBOARD_IMAGE_H_
