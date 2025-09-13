import'dart:ui';

// FlutterView view = WidgetsBinding.instance.platformDispatcher.views.first;
// Size size = view.physicalSize / view.devicePixelRatio;
// double deviceWidth = size.width;
// double deviceHeight = size.height - 37.0;

var pixelRatio = window.devicePixelRatio;

//Size in physical pixels
var physicalScreenSize = window.physicalSize;
var physicalWidth = physicalScreenSize.width;
var physicalHeight = physicalScreenSize.height;

//Size in logical pixels
var logicalScreenSize = window.physicalSize / pixelRatio;
var logicalWidth = logicalScreenSize.width;
var logicalHeight = logicalScreenSize.height;

//Padding in physical pixels
var padding = window.padding;

//Safe area paddings in logical pixels
var paddingLeft = window.padding.left / window.devicePixelRatio;
var paddingRight = window.padding.right / window.devicePixelRatio;
var paddingTop = window.padding.top / window.devicePixelRatio;
var paddingBottom = window.padding.bottom / window.devicePixelRatio;

//Safe area in logical pixels
var safeWidth = logicalWidth - paddingLeft - paddingRight;
var safeHeight = logicalHeight - paddingTop - paddingBottom;



double safePadding = 10.0;

double toolBarHeight = safePadding * 6;
var heightBottomNavigationBar = safePadding * 7;

double deviceWidth = safeWidth;
double deviceHeight = safeHeight - heightBottomNavigationBar;

double safeFontSizeBig = safeWidth * 0.069;
double safeFontSizeNormal = safeWidth * 0.044;
double safeFontSizeSmall = safeWidth * 0.022;

double safeIconSizeNormal = safeWidth * 0.06;