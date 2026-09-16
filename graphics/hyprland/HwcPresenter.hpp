#pragma once
#include "AquamarineBuffer.hpp"
#include "HwcSession.hpp"

namespace Dethyprland {
using HwcPresenter = HwcSession<Hyprutils::Memory::CSharedPointer<Aquamarine::IBuffer>>;
}
